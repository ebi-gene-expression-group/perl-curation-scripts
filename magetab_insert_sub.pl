#!/usr/bin/env perl
#
# Script to add a MAGETAB submission to the submission
# tracking database (used e.g. for FTP uploaded submissions, pipeline).
# Originally written by Tim 2007, updated Aug 2013 by Emma

=pod

=head1 NAME

magetab_insert_sub.pl - manually insert an experiment submission into the Submissions Tracking system.

=head1 SYNOPSIS

magetab_insert_sub.pl -m new_magetab.txt -l submitter_username submission_data_files.tar.gz

magetab_insert_sub.pl -i new_idf.txt -s new_sdrf.txt -l submitter_username submission_data_files.tar.gz

magetab_insert_sub.pl -m new_magetab.txt -l submitter_username -A E-MTAB-99999 -c

=head1 DESCRIPTION

This script takes a MAGE-TAB document (or separate IDF and SDRF) plus data
files, inserts a new submission into the Submissions Tracking database, and
adds a new directory to the Submissions directory containing the submitted
files.

=head1 OPTIONS

=over 2

=item -m --magetab

Filename of combined MAGE-TAB document. You must provide this OR both -i and -s
options.

=item -i --idf

Filename of IDF file. You must provide this AND -s option, OR -m option only.

=item -s --sdrf

Filename of SDRF file. You must provide this AND -i option, OR -m option only.

=item -l --login

Submitter username. Required.

=item -a --accession

Desired experiment accession. Optional.

=item -c --clobber

Overwrite any existing files for the experiment without prompting. Optional.

=item -h --help

Print a helpfile message.

=item -ne --no-email
Skip sending email to OTRS.

=back

=head1 AUTHOR

ArrayExpress and Expression Atlas team <arrayexpress-atlas@ebi.ac.uk>

=cut

use strict;
use warnings;

use Getopt::Long;
use Pod::Usage;
use Mail::Sendmail;
use DateTime;
use Log::Log4perl qw(:easy);
use ArrayExpress::AutoSubmission::DB;
use ArrayExpress::AutoSubmission::Creator;
use EBI::FGPT::Config qw($CONFIG);

# Format for log statements
Log::Log4perl->easy_init( { level => $INFO, layout => '%-5p - %m%n' } );

my $args = parse_args();

my @dataFiles = @ARGV;

# If we were passed some data files, check that they exist.
if( @dataFiles ) {
    
    INFO( "Checking that datafiles exist and are readable..." );
    foreach my $file ( @dataFiles ) {
        LOGDIE("Error: file not found: $file")
          unless ( defined($file) && -f $file && -r $file );
    }
    INFO( "All data files present and correct!" );
}
# Otherwise, warn that we weren't passed any data files.
else {
    WARN( "No data files provided." );
}

# If we have an SDRF, prepend it to @dataFiles array.
if( $args->{ "sdrf" } ) { unshift @dataFiles, $args->{ "sdrf" }; }

# If clobber was requested, warn about this.
if ( $args->{ "clobber" } ) {

	WARN( "Clobber requested: will replace any existing files");
}


# Add submission to the database.
# Use either MAGE-TAB or IDF filename for database.
my $magetabOrIdf = ( $args->{ "idf" } || $args->{ "magetab" } );

# Instantiate our Creator object.
my $creator = ArrayExpress::AutoSubmission::Creator->new(
	{
		login           => $args->{ "login" },
		name            => $magetabOrIdf,
		spreadsheet     => $magetabOrIdf,
		data_files      => [ @dataFiles ],
		accession       => $args->{ "accession" },
		experiment_type => 'MAGE-TAB',
		comment         => 'Submission inserted manually',
		clobber         => $args->{ "clobber" },
		
	}
);

# Create the experiment.
my $expt = $creator->get_experiment();

# Copy the files to the submissions directory and insert details to Submissions
# Tracking database.
$creator->insert_spreadsheet();
if( @dataFiles ) { $creator->insert_data_files() };

# Now we're all set, release the hounds.
$expt->set(
	status          => $CONFIG->get_STATUS_PENDING(),
	in_curation     => 1,
	num_submissions => ( $expt->num_submissions() + 1 ),
);

# Update the Submissions Tracking database.
$expt->update();

# sending email only if no-email arg was not provided.
if(! $args->{ "no-email" }){
	# Send mail to OTRS
	# Some variables to put in email.
	my $accession = $args->{ "accession" } || "not specified";
	my $login = $args->{ "login" };
	my $dir = $expt->filesystem_directory();

	my $from = $CONFIG->get_AUTOSUBS_ADMIN;
	my $to   = $CONFIG->get_AUTOSUBS_CURATOR_EMAIL;

	my $dt =
	  DateTime->now( time_zone => 'local' ); # Stores current date and time as datetime object
	my $date      = $dt->ymd;              # Retrieves date as a string in 'yyyy-mm-dd' format
	my $time      = $dt->hms;
	my $date_time = $date . " " . $time;
	my $subject   =
	  "Submission $magetabOrIdf inserted into the submission tracking on: " . $date_time;
	my $message =
	    "Dear Curator," . "\n\n"
	  . $magetabOrIdf
	  . " has been inserted manually into the submission tracking database with the following details:"
	  . "\n\n"
	  . "Login: "
	  . "$login" . "\n"
	  . "Accession: "
	  . "$accession" . "\n"
	  . "Appropriate directory: " . "$dir" . "\n\n"
	  . "Best regards," . "\n\n"
	  . "Your friendly neighbourhood submissions system." . "\n" . "\n"
	  . "$date_time";

	my %mail = (
		To      => $to,
		From    => $from,
		Subject => $subject,
		Message => $message
	);
	sendmail(%mail) or ERROR($Mail::Sendmail::error);
}

###############
# Subroutines #
###############

# parse_args
#   - Read command line options.
sub parse_args {

    my %args;

    my $want_help;

    GetOptions(
        "h|help"        => \$want_help,
        "i|idf=s"       => \$args{ "idf" },
        "s|sdrf=s"      => \$args{ "sdrf" },
        "m|magetab=s"   => \$args{ "magetab" },
        "l|login=s"     => \$args{ "login" },
        "a|accession=s" => \$args{ "accession" },
        "c|clobber"     => \$args{ "clobber" },
        "ne|no_email"   => \$args{ "no-email" },
    );

    # Print usage and exit if requested.
    if( $want_help ) {
        pod2usage(
            -exitval    => 255,
            -output     => \*STDOUT,
            -verbose    => 1,
        );
    }

    # Check that we've been given the correct MAGE-TAB file(s) and that they exist.
    # Either combined MAGE-TAB document:
    if( $args{ "magetab" } ) {

        unless( -r $args{ "magetab" } ) {

            pod2usage(
                -message    => "Unable to read MAGE-TAB file " . $args{ "magetab" } . "\nPlease check it exists and is readable.\n",
                -exitval    => 255,
                -output     => \*STDOUT,
                -verbose    => 1,
            );
        }
    }
    # Or separate IDF and SDRF:
    elsif( $args{ "idf" } && $args{ "sdrf" } ) {
        
        unless( -r $args{ "idf" } ) {

            pod2usage(
                -message    => "Unable to read IDF file " . $args{ "idf" } . "\nPlease check it exists and is readable.\n",
                -exitval    => 255,
                -output     => \*STDOUT,
                -verbose    => 1,
            );
        }

        unless( -r $args{ "sdrf" } ) {

            pod2usage(
                -message    => "Unable to read SDRF file " . $args{ "sdrf" } . "\nPlease check it exists and is readable.\n",
                -exitval    => 255,
                -output     => \*STDOUT,
                -verbose    => 1,
            );
        }
    }
    # If we didn't have either a combined MAGE-TAB or separate IDF+SDRF, quit.
    else {
        pod2usage(
            -message    => "You must specify EITHER MAGE-TAB document filename OR IDF and SDRF filenames.\n",
            -exitval    => 255,
            -output     => \*STDOUT,
            -verbose    => 1,
        );
    }

    # We must have submitter username, check we got this..
    unless( $args{ "login" } ) {

        pod2usage(
            -message    => "You must specify a submitter username.\n",
            -exitval    => 255,
            -output     => \*STDOUT,
            -verbose    => 1,
        );
    }

    # If an accession is provided, ensure that it is a valid one.
    if( $args{ "accession" } ) {

        unless( $args{ "accession" } =~ /^E-\w{4}-\d+$/ ) {

            pod2usage(
                -message    => "\"" . $args{ "accession" } . "\" does not look like an ArrayExpress accession.\n",
                -exitval    => 255,
                -output     => \*STDOUT,
                -verbose    => 1,
            );
        }
    }

    # If we were passed the clobber option, make sure that we also have the experiment accession.
    if( $args{ "clobber" } ) {

        unless( $args{ "accession" } ) {

            pod2usage(
                -message    => "Cannot use clobber option without an ArrayExpress accession.\n",
                -exitval    => 255,
                -output     => \*STDOUT,
                -verbose    => 1,
            );
        }
    }

    return \%args;
}


