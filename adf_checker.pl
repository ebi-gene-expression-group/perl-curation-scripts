#!/usr/bin/env perl
#
# Script to check an ADF for general formatting and content errors
#
# Amy Tang 2014, EMBL-EBI ArrayExpress Team

# $Id: adf_checker.pl

use strict;
use warnings;
use Getopt::Long;

use EBI::FGPT::Reader::ADFParser;
use EBI::FGPT::Config qw($CONFIG);

use Log::Log4perl;

my $usage = <<OUT;
    	
  Usage: $0 -i <ADF filename> -o <log file> 

  -o output log file name for reporting
     if not specifed log file adf_name.report will be used
      
  -c can be used so specify a separate file containing Composite annotation 
     (not implemented yet)
      
  -h prints this help

OUT

sub parse_args{

    my (%args, $want_help);
     
    GetOptions(
        "input|i=s"  => \$args{input},
        "output|o=s" => \$args{output},
        "help|h"     => \$want_help,        
        "composites|c=s" => \$args{composites},   
    );
    
    if ( ($args{input} and $args{subid}) or (!$args{input} and !$args{subid}) ){
        print STDERR<<OUT;

  Error: you must specify EITHER an input ADF file with -i 
                          OR a MIAMExpress submission id with -s
  
OUT
        print STDERR $usage;

        exit 255;
    }
    
    if ($want_help){
    	print STDERR $usage;
        exit;
    }
    
    return \%args;
}


########
# MAIN #
########

# Get our arguments
my $args = parse_args;

# Use default report name if none was specified
if (!$args->{output}){
    $args->{output} = $args->{input}.".report";
}

print "###### Starting ADF checking, creating MAGE-TAB ADF parser...\n\n";
my $start_time = time;

my $adf_checker = EBI::FGPT::Reader::ADFParser->new({
     'adf_path'   => $args->{input},
     'custom_log_path' => $args->{output},
});

$adf_checker->check;

# Not sure why Log4perl knows which logger I'm referring to,
# because the logger was created as part of the $adf_checker
# object and I never explicitly called for the logger object.
# Perhaps via "use EBI::FGPT::Reader::ADFParser_new;" at the top?

my $checker_status_appender = Log::Log4perl->appender_by_name("adf_checker_status")
          or die("Could not find log appender named '\adf_checker_status\'.");
      
print "\n";          
print "Number of warnings: "
      . $checker_status_appender->howmany("WARN") . "\n";
print "Number of errors: "
      . $checker_status_appender->howmany("ERROR") . "\n";
      
my $time_taken = time - $start_time;
print "\n###### Checks took $time_taken seconds\n";

# chmod report file so it can be deleted
# my $mode = 0755;
# chmod $mode, $args->{output};

exit 2 if ($adf_checker->has_errors);
exit 1 if ($adf_checker->has_warnings);
exit 0;
