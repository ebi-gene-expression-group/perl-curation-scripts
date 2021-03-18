#!/usr/bin/env perl

=head1 NAME

launch_tracking_daemons.pl
 
=head1 DESCRIPTION

Script to launch, kill checking daemons

=head1 SYNOPSIS
      
To start specific daemons:
launch_tracking_daemons.pl -p MAGE-TAB -p GEO 
      
To kill all dameons currently known to be running:
launch_tracking_daemons.pl -k
      
To kill all running daemons and then restart all default daemons:
launch_tracking_daemons.pl -r

=head1 AUTHOR

Written by Anna Farne and updated by Emma Hastings (2014) , <emma@ebi.ac.uk>
 
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

my ( @pipelines, $restart, $kill, $help );

GetOptions(
	"p|pipeline=s" => \@pipelines,
	"r|restart"    => \$restart,
	"h|help"       => \$help,
	"k|kill"       => \$kill,
);

my $usage = <<END;
    Usage: 

      To start specific daemons:
      launch_tracking_daemons.pl -p GEO -p MAGE-TAB
      
      To kill all dameons currently known to be running:
      launch_tracking_daemons.pl -k
      
      To kill all running daemons and then restart all default daemons:
      launch_tracking_daemons.pl -r

END

if ($help) {
	print $usage;
	exit;
}

if ( $restart or $kill ) {
	print
"** This will kill ALL tracking daemons currently running **\nContinue? (y/n)\n";
	my $answer = <>;
	die unless $answer =~ /^y/i;

	# Get list of pids from subs tracking.
	my $result =
	  ArrayExpress::AutoSubmission::DB::DaemonInstance->search( running => 1 );

	# Kill all running daemons
	my @pids;
  PID: while ( my $daemon = $result->next ) {
		my $pid = $daemon->pid;

		# Use grep to check that the process we are about to kill
		# has the name we expect it to have
		my $name_suffix =
		  $daemon->pipeline_id->submission_type . "." . $daemon->daemon_type;

		my $rc = system("ps $pid | grep $name_suffix");

		if ($rc) {
			$log->warning(
"Process $pid with name $name_suffix not found. Updating daemon status to not running"
			);
			$daemon->set( running => 0, end_time => date_now() );
			$daemon->update();
			next PID;
		}

		push @pids, $pid;
		$log->info("Killing $pid ($name_suffix)");
		kill "USR1", $pid
		  or $log->warning("Could not send kill signal to process $pid. $!");
	}

	# poll every 5 seconds until they are all gone
	my @still_alive;
  TEST: for ( 0 .. 16 ) {
		unless ( @still_alive = grep { kill 0, $_ } @pids ) {
			last TEST;
		}
		sleep 5;
	}

	# Die if any are still alive after 1 minute
	if (@still_alive) {
		my $message =
"Could not kill all daemons. The following processes were still alive after 1 minute"
		  . join "\n", @still_alive . "\n";
		$log->log_and_die( level => 'alert', message => $message );
	}

}

if ($kill) {
	$log->info("Killing daemons done");
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

			# Store pid in subs tracking
			ArrayExpress::AutoSubmission::DB::DaemonInstance->insert(
				{
					pipeline_id => $pipeline->id,
					daemon_type => $type,
					pid         => $pids[0],
					start_time  => date_now(),
					running     => 1,
					user        => getlogin,
				}
			);

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

		# Record that the process has died

		my @results = ArrayExpress::AutoSubmission::DB::DaemonInstance->search(
			running => 1,
			pid     => $pid,
		);

		if ( my $di = $results[0] ) {
			$di->set( running => 0, end_time => date_now() );
			$di->update;
		}

		$dead{$pid} = 1;
	}

	if ( scalar(@dead_pids) == scalar(@child_pids) ) {

		# They are all dead - we can exit
		exit;
	}
	sleep 2;
}

