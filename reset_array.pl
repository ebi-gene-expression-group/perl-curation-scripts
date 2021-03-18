#!/usr/bin/env perl
#
# Script to reset a MAGE-TAB array submission to pending, or check.
# Currently doesn't work with any databases except for Submissions Tracking
# database and doesn't expect the ADF to have a submissions directory
# on the file system. The script deals directly with the ADF that lives
# in the AE2 LOAD directory, where curation will be done and file(s) to be
# loaded into AE2 PROD database will be sourced.
#
# $Id: reset_array.pl

# Author: Amy Tang (amytang@ebi.ac.uk), March 2014


use strict;
use warnings;

use DBI;
use Getopt::Long;

use Log::Log4perl qw(:easy);

use EBI::FGPT::Config qw($CONFIG);

use EBI::FGPT::Common qw(
    date_now 
    check_linebreaks 
);

use EBI::FGPT::Reader::ADFParser;
use ArrayExpress::AutoSubmission::DB::ArrayDesign;

# Format for log statements
Log::Log4perl->easy_init( { level => $INFO, layout => '%-5p - %m%n' } );

my ($accession, $pending, $check);

GetOptions(
        "a|accession=s" => \$accession,
        "p|pending!"    => \$pending,
        "c|check!"      => \$check,
    );

unless ( ( $pending || $check ) && $accession ) {
        print <<"NOINPUT";
Usage: reset_array.pl -a <accession> <pending or checking flag> 

Options (select either -c or -p):  
          -c   re-check submission by triggering adf_checker.pl script.
               will return checking result status (pass or fail) to Subs Tracking DB.

          -p   set submission to pending status for user editing or cron job to pick up
          
NOINPUT

        exit 255;
}

umask 002;

# Check that accession is valid.
unless( $accession =~ /^A-\w{4}-\d+$/ ) {
    LOGDIE( "\"$accession\" is not a valid array design accession." );
}

        
if ($pending){
    update_sub_tracking($accession, $CONFIG->get_STATUS_PENDING);
    
} elsif ($check) {

    # update submission tracking status to "checking"
    
    my $array = update_sub_tracking($accession, $CONFIG->get_STATUS_CHECKING);    

    my $adf_path = $array->file_to_load;  # Not sure why the method call isn't "get_fild_to_load"...
        
    print "\n### Starting ADF checking for $accession. ADF: $adf_path..\n";

    my $start_time = time;
    
    # Convert mac to unix
    mac2unix($adf_path);
    my $adf_checker = EBI::FGPT::Reader::ADFParser->new({
         'adf_path'   => $adf_path,
    });
  
    
    # Attempt to check ADF file
    eval{
        $adf_checker->check;            
    };
    
    if($@){
        update_sub_tracking($accession, $CONFIG->get_STATUS_CRASHED, "ADF checking crashed with error: $@");
        die "ADF checking crashed with error: $!";
    }
    
    my $time_taken = time - $start_time; 
    print "### Finished ADF checking, which took $time_taken seconds\n\n";
            
    if ($adf_checker->has_errors){
        update_sub_tracking($accession, $CONFIG->get_STATUS_FAILED);
    }

    elsif ($adf_checker->has_warnings && !$adf_checker->has_errors){  # amytang warnings only, no errors.                                      
        my $checker_status_appender = Log::Log4perl->appender_by_name("adf_checker_status")
          or die("Could not find log appender named '\adf_checker_status\'.");                                                      
       
        WARN ( "There are " . $checker_status_appender->howmany('WARN') .
               " warnings. Check log files before you load into database!" );
        update_sub_tracking($accession, $CONFIG->get_STATUS_COMPLETE);
    }
    else{
        update_sub_tracking($accession, $CONFIG->get_STATUS_COMPLETE);
    }
} 


sub update_sub_tracking{

	my ($accession, $status, $comment) = @_;

	my $array = ArrayExpress::AutoSubmission::DB::ArrayDesign->find_or_create({
	            accession => $accession,
	            is_deleted => 0,
	            });
    
    $array->set(
         status              => $status,
         date_last_processed => date_now(),
         comment             => $comment, 
    );
    $array->update();

    INFO ("ADF $accession successfully updated to status \'$status\'.");
    return $array;
}


sub mac2unix{
	my ($file) = @_;
	
	my ($counts, $le) = check_linebreaks($file);
	
	if ($counts->{mac}){
		print "Converting mac line endings to unix for file $file\n";
		my @args = ('/usr/bin/perl','-i','-pe','s/\r/\n/g',$file);
	    system (@args) == 0
	        or die "system @args failed: $?";
	}
	return;
}
