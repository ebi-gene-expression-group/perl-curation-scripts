#!/usr/bin/env perl
#
#
# $Id: check_atlas_eligibility.pl 23399 2013-04-05 13:32:55Z amytang $
#

use strict;
use warnings;

=pod

=head1 NAME

check_atlas_eligiblity.pl - a script to check that a MAGETAB experiment is suitable
for loading into ArrayExpress Gene Expression Atlas

=head1 SYNOPSIS

=over 2

   check_atlas_eligibility.pl -i <IDF file>

   check_atlas_eligibility.pl -m <Merged IDF and SDRF file>

=back

=head1 DESCRIPTION

Script performs basic content validation on the supplied MAGE-TAB file. Note that this script will only attempt to
resolve references within the given file/files. Any reference which has a Term Source REF value of 'ArrayExpress'
is assumed to be available in ArrayExpress and the loader will check this at a later stage. This content validation
does not replace the full set of checks performed by expt_check.pl, it is a subset of these checks.

The script will return 0 if the file is considered safe to load.

=head1 OPTIONS

=over 4

=item B<-i> C<IDF filename>

The MAGE-TAB IDF file to be checked (SDRF file name will be obtained from the IDF)

=item B<-m> C<Merged MAGE-TAB IDF and SDRF filename>

A MAGE-TAB document in which a single IDF and SDRF have been combined (in that order),
with the start of each section marked by [IDF] and [SDRF] respectively. Note that such
documents are not compliant with the MAGE-TAB format specification; this format is used
by ArrayExpress to simplify data submissions.

=item B<-d> C<data directory>

Directory where the data files and SDRF can be found if they are not in the same directory
as the IDF

=item B<-x>

Skips checking for the presence of raw and processed data files

=item B<-w>

A boolean flag to signal that the Atlas error code needs to be written back to the Submissions
Tracking database.

=item B<-a>

Used in conjunction with -w flag, the accession number (a string) of the experiment which needs
Atlas error code written to the Submissions Tracking database.

=item B<-v>

Use for verbose logging output.

=item B<-h>

Prints a short help text.

=back

=head1 TESTS


=head1 AUTHOR

Amy Tang (amytang@ebi.ac.uk) and Anna Farne (farne@ebi.ac.uk),
ArrayExpress team, EMBL-EBI, 2012-2013.

Many of the experiment checks were implemented by Tim Rayner.

Acknowledgements go to the ArrayExpress curation team for feature
requests, bug reports and other valuable comments.

=cut

use Pod::Usage;
use Getopt::Long qw(:config no_ignore_case);
use File::Spec;
use Data::Dumper;

use EBI::FGPT::Reader::MAGETAB;
use EBI::FGPT::Common qw(date_now);

use ArrayExpress::AutoSubmission::DB::Experiment;


sub parse_args {

    my ( %args, $want_help );
    GetOptions(
        "m|merged=s"    => \$args{ "merged_filename" },
        "i|idf=s"       => \$args{ "idf_filename" },
        "x|skip!"       => \$args{ "skip_data_checks" },
        "w|write!"      => \$args{ "write_error_codes" },
        "a|accession=s" => \$args{ "accession" },
        "h|help"        => \$want_help,
        "d|data_dir=s"  => \$args{ "data_dir" },
        "v|verbose"     => \$args{ "verbose" }
    );

    if ($want_help) {
        pod2usage(
            -exitval => 255,
            -output  => \*STDOUT,
            -verbose => 1,
        );
    }

    unless ( $args{merged_filename} || $args{idf_filename} ) {
        pod2usage(
            -message => 'You must provide an IDF or merged IDF/SDRF file.',
            -exitval => 255,
            -output  => \*STDOUT,
            -verbose => 0,
        );
    }

    if ($args{idf_filename} and $args{merged_filename}) {
       pod2usage(
 	    -message => 'You cannot provide an IDF AND merged IDF/SDRF file.',
	    -exitval => 255,
	    -output  => \*STDOUT,
	    -verbose => 0,
        )
    }

    if ($args{write_error_codes} && !$args{accession}) {
       pod2usage(
 	    -message => 'You must use both the -w and -a options to write error codes back to submissions tracking database.',
	    -exitval => 255,
	    -output  => \*STDOUT,
	    -verbose => 0,
        )
    }

    return ( \%args );
}

# Checker will always perform basic validation checks
# when the MAGE-TAB files are parsed.
# Here we specify that it runs additional checks as required
my $check_sets = {
	'EBI::FGPT::CheckSet::AEAtlas' => 'ae_atlas_eligibility',
};

# Get our arguments
my $args = parse_args();

# Set up parser params depending on script args provided
my $reader_params->{ "check_sets" } = $check_sets;
$reader_params->{ "skip_data_checks"} = $args->{ "skip_data" };

# Variable to store either IDF filename or merged MAGE-TAB filename.
my $filename;

# Populate the $filenme variable.
if( $args->{ "idf_filename" } ) {
	$reader_params->{ "idf" } = $args->{ "idf_filename" };
	$filename = $args->{ "idf_filename" };
}
else {
	$reader_params->{ "mtab_doc" } = $args->{ "merged_filename" };
	$filename = $args->{ "merged_filename" };
}

# Set the data directory. If it's been specified, use that.
if( $args->{ "data_dir" } ) {
	$reader_params->{ "data_dir" } = $args->{ "data_dir" };
}
# If not, figure out the directory based on the MAGE-TAB path.
else {

    my ( $vol, $dir, $file ) = File::Spec->splitpath( $filename );

    # If the directory is missing, use the current working dir.
	$dir ||= ".";

	$reader_params->{ "data_dir" } = $dir;
}

print "\nData dir: " . $reader_params->{ "data_dir" } . "\n\n";

# Skip checks on data files if asked.
if( $args->{ "skip_data_checks" } ) {
	$reader_params->{ "skip_data_checks" } = $args->{ "skip_data_checks" };
}

if( $args->{ "verbose" } ) {
    $reader_params->{ "verbose_logging" } = 1;
}

# Create a new MAGE-TAB reader.
my $checker = EBI::FGPT::Reader::MAGETAB->new( $reader_params );

# Run the checks by calling the parse() function of the MAGE-TAB reader.
$checker->parse();

# Prints how many errors and warnings we've got from the basic parsing and
# Atlas-specific checks to STDOUT.
$checker->print_checker_status();

# Print the atlas eligibility fail codes to STDOUT
my $eligibility_check_set = $checker->get_check_set_objects->{ "EBI::FGPT::CheckSet::AEAtlas" };

# Flag to set if the experiment has failed any checks.
my $atlas_check_failed = 0;

# String for the atlas fail codes for printing.
my $atlas_fail_code_string;

# Go through the check sets, log the error codes if any.
if( $eligibility_check_set ) {

    print "Atlas eligibility fail codes: ";

    # If this checkset has fail codes.
    if( scalar @{ $eligibility_check_set->get_atlas_fail_codes } ) {

        # Set the flag.
        $atlas_check_failed = 1;

        # Get the unique codes from the check set.
        my %unique_codes = map { $_ => 1 } @{ $eligibility_check_set->get_atlas_fail_codes };

        $atlas_fail_code_string = join ", ", sort {$a <=> $b} keys %unique_codes;

    }
    # If there are no fail codes, we passed all checks.
    else {
        $atlas_fail_code_string = "PASS";
    }

    print STDOUT "$atlas_fail_code_string\n";
}

# If we have an accession and have been asked to write the error codes to the
# subs tracking DB, do that.
if( $args->{ "write_error_codes" } && $args->{ "accession" } ) {

    my @experiments
        = ArrayExpress::AutoSubmission::DB::Experiment->search_like(
            accession       => $args->{ "accession" },
            is_deleted      => 0,
        );

    # If we got an experiment from the database, we can update the record.
    if ( scalar @experiments == 1 ) {

        # Get the experiment object.
        my $experiment = $experiments[ 0 ];

        # Get the current time.
        my $update_time = date_now();

        # Update the experiment object with the fail codes and the update time.
        $experiment->set(
            atlas_fail_score => $atlas_fail_code_string,
            date_last_processed => $update_time,
        );

        # Try to update the subs tracking database.
        eval {
            $experiment->update();
        };

        # If the eval was successful, log this; otherwise log that it wasn't.
        if ( ! $@ ) {
            print STDOUT (
                "Atlas fail codes for experiment " . $args->{ "accession" } . " successfully updated in submissions tracking database.\n",
            );
        } else {
            print STDOUT "Could not write Atlas fail codes to submissions tracking database.\n";
        }
    }
}

# Finally, if there were any errors, the script exits with 1. This is so that
# when the script is called by a Conan pipeline, Conan can see whether the job
# was successful from the exit code of the script.
if ( ( $checker->has_errors ) || ( $atlas_check_failed == 1 ) ) {
	exit 1;
}
else {
	exit 0;
}
