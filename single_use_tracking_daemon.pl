#!/usr/bin/env perl

=head1 NAME

launch_tracking_daemons.pl

=head1 DESCRIPTION

Script to launch a daemon with stop parameter and no writing to DB

=head1 SYNOPSIS

To start a specific daemons:
launch_tracking_daemons.pl -p MAGE-TAB -s

=head1 AUTHOR

Originally written by Anna Farne and updated by Emma Hastings (2014)
modified by Anja Fullgrabe (2021)

=head1 COPYRIGHT AND LICENSE

Copyright [2011] EMBL - European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the
"License"); you may not use this file except in compliance
with the License. You may obtain a copy of the License at
http://www.apache.org/licenses/LICENSE-2.0
Unless required by applicable law or agreed to in writing,
software distributed under the License is distributed on an
"AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
either express or implied. See the License for the specific
language governing permissions and limitations under the
License.

=cut

use strict;
use warnings;

use Data::Dumper;
use Getopt::Long;
use English;
use POSIX ":sys_wait_h";
use File::Temp qw(tempfile);
use Log::Dispatch;

use EBI::FGPT::Config qw($CONFIG);
use EBI::FGPT::Common qw(date_now);

use ArrayExpress::AutoSubmission::DB::Pipeline;
use ArrayExpress::AutoSubmission::DB::DaemonInstance;

$| = 1;

my $log = Log::Dispatch->new(
	outputs => [
		[
			'Screen',
			min_level => 'debug',
			newline   => 1
		]
	],
);

my ( @pipelines, $help, $stop );

GetOptions(
	"p|pipeline=s" => \@pipelines,
	"h|help"       => \$help,
	"s|stop"       => \$stop,
);

my $usage = <<END;
    Usage:

      To start specific daemon and stop it after use:
      launch_tracking_daemons.pl -p MAGE-TAB -s

END

if ($help) {
	print $usage;
	exit;
}


# Get the pipeline objects from names specified by user
my @pipeline_objects;
if (@pipelines) {
	foreach my $pl (@pipelines) {
		my @results =
		  ArrayExpress::AutoSubmission::DB::Pipeline->search(
			submission_type => $pl );

		# If we dont recognise pipeline requested we die
		unless (@results) {
			$log->log_and_die(
				level   => 'alert',
				message => "Could not find pipeline with name $pl\n"
			);
		}
		push @pipeline_objects, $results[0];
	}
}
else {

	# Or get list of defaults from subs tracking
	my $result = ArrayExpress::AutoSubmission::DB::Pipeline->retrieve_all;
	while ( my $pipeline = $result->next ) {
		if ( $pipeline->instances_to_start ) {
			my $num = $pipeline->instances_to_start - 1;
			for ( 0 .. $num ) {
				push @pipeline_objects, $pipeline;
			}
		}
	}
}

my @child_pids;
foreach my $pipeline (@pipeline_objects) {

	# Get pipeline parameters from subs tracking

	# Submission type i.e. MAGE-TAB and GEO
	my $submis_type = $pipeline->submission_type;

	#  rpetry: We no longer run exporter_deamon  TYPE: foreach my $daemon ( "checker_daemon", "exporter_daemon" ) {
	foreach my $daemon ( "checker_daemon" ) {

		# Example of type: MAGETABChecker
		my $type = $pipeline->$daemon;
		next TYPE unless defined($type);

# Create a temp file to store pid,
# suspect only stores pid of child processs as parent ones are written to database
# Also this file seems to disappear once pid is written into database
		my $pidfile =
		  File::Temp::tempnam( $CONFIG->get_AUTOSUBMISSIONS_FILEBASE,
			"$submis_type.$type" );

		my $pid = fork();

		# The child returns from the fork() with a
		# value of 0 to signify that it is the child pseudo-process.
		if ( $pid == 0 ) {

			# child
			# Spawn daemon
			$PROGRAM_NAME .= ".$submis_type.$type";

		   # Example of class: EBI::FGPT::AutoSubmission::Daemon::MAGETABChecker
			my $daemon_class = "EBI::FGPT::AutoSubmission::Daemon::" . $type;

            # Checking this is a valid class for which we have a module installed.
			eval "use $daemon_class";
			if ($@) {
				die "Could not load $daemon_class. $!, $@";
			}

			my $threshold;
			my $comma_and_space = qr(\s*,\s*);

			foreach
			  my $level ( split $comma_and_space, $pipeline->checker_threshold )
			{
				my $get_level = "get_$level";
				if ($threshold) {
					$threshold = ( $threshold | $CONFIG->$get_level );
				}
				else {
					$threshold = $CONFIG->$get_level;
				}
			}

		  # Common daemon atts, most values come from pipeline table of database
			my %atts = (
				polling_interval  => $pipeline->polling_interval,
				experiment_type   => $submis_type,
				checker_threshold => $threshold,
				autosubs_admin    => $CONFIG->get_AUTOSUBS_ADMIN(),
				accession_prefix  => $pipeline->accession_prefix,
				pidfile           => $pidfile,
				quit_when_done    => $stop,
			);

			# Exporter sepcific atts
			if ( $daemon eq "exporter_daemon" ) {
				$atts{pipeline_subdir}     = $pipeline->pipeline_subdir;
				$atts{keep_protocol_accns} = $pipeline->keep_protocol_accns;
			}

			my $daemon_instance = $daemon_class->new( \%atts );
			$daemon_instance->run;
			exit(0);
		}
		elsif ($pid) {

			# parent

			# Sleep for a few secs to allow pid file to be written by child
			sleep 5;

			open( my $pid_fh, "<", $pidfile )
			  or $log->log_and_die(
				level   => 'alert',
				message =>
				  "Could not open temp pid file $pidfile for reading. $!" . "\n"
			  );

			my @pids = <$pid_fh>;
			push( @child_pids, $pids[0] );

			unlink $pidfile;
		}
		else {
			$log->log_and_die(
				level   => 'alert',
				message =>
				  "Couldn't fork to create $submis_type $type daemon: $!" . "\n"
			);
		}
	}
}
$log->info("Waiting for child processes...");

# Monitor daemon processes
my %dead;
while (1) {
	my @dead_pids = grep { ( kill 0, $_ ) == 0 } @child_pids;

  PID: foreach my $pid (@dead_pids) {

		# Skip if we've already handled this
		chomp $pid;
		next PID if $dead{$pid};
		$log->info("$pid is dead");

		$dead{$pid} = 1;
	}

	if ( scalar(@dead_pids) == scalar(@child_pids) ) {

		# They are all dead - we can exit
		exit;
	}
	sleep 2;
}
