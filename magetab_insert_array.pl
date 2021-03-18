#!/usr/bin/env perl
#
# Script to add a MAGE-TAB ADF manually to the submission tracking database.
# ADF file is NOT written into any submissions directory but straight into
# the appropriate AE2 LOAD directory.
# Loosely based on magetab_insert_sub.pl (written by Emma Hastings, emma@ebi.ac.uk).
#
# Author: Amy Tang (amytang@ebi.ac.uk), March 2014

=pod

=head1 NAME

magetab_insert_array.pl - manually insert an array design submission into the Submissions Tracking system.

=head1 SYNOPSIS

magetab_insert_array.pl -f new_adf.txt

magetab_insert_array.pl -f new_adf.txt -l submitter_login

magetab_insert_array.pl -f new_adf.txt -l submitter_login -a A-MTAB-99999 -c

=head1 DESCRIPTION

This script takes an ADF document, inserts a new entry into the submissions
tracking database, and adds a new directory to the AE2 load directory.

=head1 OPTIONS

=over 2

=item -f --file

Required. Name of array design file.

=item -l --login

Optional. Submitter user name. If not provided, will use fg_cur.

=item -a --accession

Optional. Desired accession for this array design. If not provided will use
next available accession from Submissions Tracking database.

=item -c --clobber

Optional. Replace existing files without prompting.

=item -h --help

Print a helpful message.

=back

=head1 AUTHOR

ArrayExpress and Expression Atlas team <arraexpress-atlas@ebi.ac.uk>

=cut

use strict;
use warnings;

use File::Copy;

use Getopt::Long;

use Mail::Sendmail;
use DateTime;

use Pod::Usage;
use Log::Log4perl qw(:easy);

use EBI::FGPT::Config qw($CONFIG);
use EBI::FGPT::Common qw(date_now ae2_load_dir_for_acc);

use ArrayExpress::AutoSubmission::DB::ArrayDesign;

# Format for log statements
Log::Log4perl->easy_init( { level => $INFO, layout => '%-5p - %m%n' } );

my $args = parse_args();

if ( $args->{ "clobber" } ) {
	WARN("Clobber requested: will replace any existing files");
}

# Try to parse out Array Design Name from the MAGE-TAB ADF header.
# If that fails, just use the ADF file name.

my $adf_name,

my ( $vol, $dir, $adf_file_name ) = File::Spec->splitpath( $args->{ "filename" } );

open (IN, $args->{ "filename" } ) || LOGDIE ("Can't open ADF file to check for ADF name.");
while (<IN>) {
    if ( $_=~/^Array Design Name/ ) {
        chomp $_;
        my @line = split ("\t", $_);
        $adf_name = $line[1];
    }
}
close IN;

if (!$adf_name) {
    $adf_name = $adf_file_name;
}

my $default_user = $CONFIG->get_AUTOSUBS_ADMIN_USERNAME;
my $login = ( $args->{ "login" } || $default_user );

if( $login eq $default_user ) {
    WARN( "Using curator login as submitter user name." );
}

# Before creating the ArrayDesign object for SubsTracking,
# the accession prefix needs to be defined otherwise the code will
# break in ArrayExpress::AutoSubmission::DB::Accessionable.
# This is hardcoded to be A-MTAB- as we're moving away from MIAMExpress
# completely.

ArrayExpress::AutoSubmission::DB::ArrayDesign->accession_prefix('A-MTAB-');

# Initiate the ArrayExpress::AutoSubmission::DB::ArrayDesign object.
# Set miamexpress_subid undefined (don't use '' or "NULL" as in both
# cases a subid of "0" would be inserted into the database).
# Previously we didn't set the NULL constraint on the subid;
# "find_or_create" ended up hijacking old entries in the Subs Tracking DB
# which have no accession but have existing miamexpress_subid.

my $array = ArrayExpress::AutoSubmission::DB::ArrayDesign->find_or_create (
    miamexpress_subid => undef,
    accession  => $args->{ "accession" },
	is_deleted => 0,
);

unless ($array) {
    LOGDIE ("Can't find or create the ADF entry in Submissions Tracking database by ArrayExpress accession.");
}

# The assigned_accession variable is needed because accession can be hard-coded upfront
# or assigned by Subs Tracking (auto-increment)

my $assigned_accession= $array->get_accession;
INFO ("Specified/assigned accession is $assigned_accession\n");

my $ae2_adf_load_path = File::Spec->catfile( ae2_load_dir_for_acc($assigned_accession),
                                             "$assigned_accession.adf.txt" );

$array->set(
    miamexpress_login => $login,
    name => $adf_name,
    date_last_processed => date_now(),
    status => $CONFIG->get_STATUS_PENDING,
    file_to_load        => $ae2_adf_load_path,
);

eval {
    $array->update;
};

if ($@) {
    LOGDIE ("Can't update Submissions Tracking DB with 'pending' status and the ADF AE2 LOAD path location.");
}

# Create file path for backing up the user-submitted original file, with time-stamp imprint:

my $dt = DateTime->now( time_zone => 'local' );
my $date_time = $dt->ymd."_".$dt->hms("_");  # enforces underscore delimiter between H/M/S

my $adf_orig_backup_path = File::Spec->catfile( ae2_load_dir_for_acc($assigned_accession),
                                                "$adf_file_name"."_orig_".$date_time.".txt" );

# Copy the ADF file from the local directory to the AE2 LOAD directory destination.
# Need to take care of "clobber" option and whether the file already exists in the destination

if (!$args->{ "clobber" } && -e $ae2_adf_load_path ) {

    print STDERR "In LOAD directory, $ae2_adf_load_path already exists. Do you want to overwrite it? (y/n) ";
    chomp( my $response = lc <STDIN> );

    if ($response eq 'y') {
        unlink($ae2_adf_load_path) or LOGDIE("Error removing old spreadsheet $ae2_adf_load_path, $!");
        copy_and_backup_file($args->{ "filename" }, $ae2_adf_load_path, $adf_orig_backup_path);
    }
    else {
        WARN("Old file $ae2_adf_load_path is not replaced. No new backup file was made");
    }
}

elsif ($args->{ "clobber" } && -e $ae2_adf_load_path ) {

    WARN ("In LOAD directory, $ae2_adf_load_path file already exists, overwriting because option clobber is used.");

    unlink($ae2_adf_load_path) or LOGDIE("Error removing old spreadsheet $ae2_adf_load_path: $!");
    copy_and_backup_file($args->{ "filename" }, $ae2_adf_load_path, $adf_orig_backup_path);

} else {

    copy_and_backup_file($args->{ "filename" }, $ae2_adf_load_path, $adf_orig_backup_path);

}

# Send mail to curators

my $from = $CONFIG->get_AUTOSUBS_ADMIN;
unless( $from ) {
    LOGDIE( "Could not find email address to send FROM in ArrayExpress Site Config." );
}

my $to   = $CONFIG->get_AUTOSUBS_CURATOR_EMAIL;
unless( $to ) {
    LOGDIE( "Could not find email address to send TO in ArrayExpress Site Config." );
}


my $dt2 =
  DateTime->now( time_zone => 'local' ); # Stores current date and time as datetime object
my $date      = $dt2->ymd;               # Retrieves date as a string in 'yyyy-mm-dd' format
my $time      = $dt2->hms;
my $date_time2 = $date . " " . $time;
my $subject   =
  "ADF $adf_name inserted into the submission tracking on: " . $date_time2;
my $message =
  "Dear Curator," . "\n\n"
  . "ADF '". $adf_name. "'"
  . " has been inserted manually into the submission tracking database with the following details:"
  . "\n\n"
  . "Login: "
  . "$login" . "\n"
  . "Accession: "
  . "$assigned_accession" . "\n"
  . "Appropriate directory: " . "$ae2_adf_load_path" . "\n\n"
  . "Best regards," . "\n\n"
  . "Your friendly neighbourhood submissions system." . "\n" . "\n"
  . "$date_time2";

my %mail = (
	To      => $to,
	From    => $from,
	Subject => $subject,
	Message => $message
);

sendmail(%mail) or ERROR($Mail::Sendmail::error);

INFO ("Email sent to $from.");


# copy_and_backup_file
#    - Copy file to load directory and back up.
sub copy_and_backup_file {

    my ($adf_path, $load_path, $backup_path) = @_;

    copy($adf_path, $load_path) or LOGDIE ("Error copying ADF from $adf_path to $load_path !", $! );

    # Insert the accession as a comment at the very top of the MAGE-TAB header
    # of the submitted ADF, before it is moved to the AE2 LOAD directory.
    # Without this comment, the ADF won't be loadable into AD2 DB via Conan,
    # and curator will have to add the accession manually.
    # Adapted code from http://www.tek-tips.com/faqs.cfm?fid=6549

    my $acc_comment="Comment[ArrayExpressAccession]\t$assigned_accession\n";

    {
       local @ARGV = ($load_path);
       local $^I = '';  # this indicates in-file editing without creating new files (otherwise new extension will be inside the quotes)
       while(<>){
          if ($. == 1) {
             print "$acc_comment";
             print $_;
          }
          else {
             print;
          }
       }
    }

    INFO "Copied ADF file to $load_path. ADF contains accession number comment in header.\n";

    copy($adf_path, $backup_path) or LOGDIE ("Error copying ADF from $adf_path to $backup_path !", $! );
    system("chmod 444 $backup_path");
    INFO "Backed up ADF file as readonly $backup_path.\n";

}


# parse_args
#   - Get options from command line
sub parse_args {

    my %args;

    my $want_help;

    GetOptions(
        "h|help"        => \$want_help,
        "f|file=s"       => \$args{ "filename" },
        "l|login=s"     => \$args{ "login" },
        "a|accession=s" => \$args{ "accession" },
        "c|clobber"    => \$args{ "clobber" }
    );

    # Print usage and exit if requested.
    if( $want_help ) {
        pod2usage(
            -exitval    => 255,
            -output     =>\*STDOUT,
            -verbose    => 1,
        );
    }

    # Check that we've been given an ADF filename.
    unless( $args{ "filename" } ) {
        pod2usage(
            -message    => "You must specify an ADF filename.\n",
            -exitval    => 255,
            -output     => \*STDOUT,
            -verbose    => 1,
        );
    }

    # Check that the ADF exists and is readable.
    unless( -r $args{ "filename" } ) {
        pod2usage(
            -message    => "Unable to read ADF file " . $args{ "filename" } . "\nPlease check it exists and is readable.\n",
            -exitval    => 255,
            -output     => \*STDOUT,
            -verbose    => 1,
        );
    }

    # If we've been given an accession check that it's a valid one.
    if( $args{ "accession" } ) {

        unless( $args{ "accession" } =~ /^A-\w{4}-\d+$/ ) {
            pod2usage(
                -message    => "\"" . $args{ "accession" } . "\" is not a valid array design accession.\n",
                -exitval    => 255,
                -output     => \*STDOUT,
                -verbose    => 1,
            );
        }
    }

    return \%args;
}
