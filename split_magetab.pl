#!/usr/bin/env perl
use strict;
use warnings;

## split_magetab.pl uses merged magetab which inludes IDF+SDRF as argument file 
## to split into two files IDF and SDRF
## Author : Suhaib Mohammed (suhaib@ebi.ac.uk), ExpresssionAtlas team, EBI, 2017.

my $filename = $ARGV[0];  
 
if (!$filename){
		print "MAGE-TAB file not provided"."\n";
		print "Usage: split_magetab.pl GSE36552.idf.txt"."\n";
   }
 
open (my $in_fh, '<', $filename) or die $!;    
my @words = split /[.]/, $filename;
my $expAcc = $words[0];


 print "Splitting IDF from MAGE-TAB for $expAcc"."\n";
 idf_split($in_fh, $expAcc);
	
 print "Splitting SDRF from MAGE-TAB for $expAcc"."\n";
 sdrf_split($in_fh, $expAcc);

 close $in_fh;

#####################
# function idf_split
#####################
sub idf_split {
 my ( $infile, $exp ) = @_; 
 my @lines;
	while ( my $line = <$infile> ) { 
		next if $line =~ m/\[IDF/;
		# in an list context, this will slurp the rest of the file.
		push (@lines, $line);
	  if ($line =~ m/\[SDRF/){
		  last;
	  }
		open(my $outfile, '>', "$exp-idf.txt") or die $!;
		print $outfile @lines;
     }
}

 #####################
# function sdrf_split
#####################     
sub sdrf_split {
 my ( $infile, $exp ) = @_; 
 my @lines;
		while ( my $line = <$infile> ) { 
		next if $line =~ m/\[SDRF/;
		# in an list context, this will slurp the rest of the file.
		push (@lines, $line);
	  if (eof()){
		  last;
	  }
		open(my $outfile, '>', "$exp-sdrf.txt") or die $!;
		print $outfile @lines;
     }
}
