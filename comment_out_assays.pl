#!/usr/bin/env perl
=pod

=head1 NAME

comment_out_assays.pl - comment out assays in an Atlas experiment XML config file.

=head1 SYNOPSIS

comment_out_assays.pl -c E-MTAB-5214-configuration.xml -l list_of_missing_runs.txt -m "The following run was excluded due to low quality"

=head1 DESCRIPTION

This script takes an experiment config filename, a filename for a list of assay
names (or run accessions), and a message as to why the assay is being excluded.
It comments out the assays in the list in the XML file, and adds the message on
the line before each of them.

Note the same "reason" message is used for all assays, so if you wanted to
comment out sets of assays for different reasons, you'd need to do them in
separate batches with this script.

=head1 OPTIONS

=over 2

=item -c

Required. Path to experiment XML config file.

=item -l

Required. Path to file containing list of missing assays.

=item -m

Required. Short message containing reason why the assays are being commented
out. Must be in quotes otherwise only the first word will be taken.

=back

=head1 AUTHOR

Expression Atlas team <arrayexpress-atlas@ebi.ac.uk>

=cut

use strict;
use warnings;
use 5.10.0;

use Getopt::Long;
use Data::Dumper;

my $args = parse_args();

my $assaysToComment = [];

open( my $fh, "<", $args->{ "list_filename" } ) 
    or die( 
    "Cannot open ",
    $args->{ "list_filename" },
    " : $!\n"
);

while( my $line = <$fh> ) {
    chomp $line;
    if( $line =~ /\s/ ) {
        die "Please provide assay names one per line.\n";
    }

    push @{ $assaysToComment }, $line;
}
close $fh;

open( my $xmlFH, "<", $args->{ "config_filename" } )
    or die(
    "Cannot open ",
    $args->{ "config_filename" },
    " : $!\n"
);

open( my $newFH, ">", $args->{ "config_filename" } . ".new" );

while( my $line = <$xmlFH> ) {
    chomp $line;

    my $assayFound = 0;

    foreach my $assayToComment ( @{ $assaysToComment } ) {

        if( $line =~ />$assayToComment</ ) { $assayFound++; }
    }
    if( $assayFound ) {
        say $newFH "                <!-- " . $args->{ "message" } . " -->";
        $line =~ s/^\s+//;
        say $newFH "                <!--$line-->";
    }
    else {
        say $newFH $line;
    }
}

close $xmlFH;
close $newFH;


sub parse_args {

    my %args;

    my $want_help;

    GetOptions(
        "h"     => \$want_help,
        "c=s"   => \$args{ "config_filename" },
        "l=s"   => \$args{ "list_filename" },
        "m=s"   => \$args{ "message" }
    );

    if( $want_help ) {
        pod2usage(
            -exitval    => 255,
            -output     => \*STDOUT,
            -verbose    => 1
        );
    }

    unless( $args{ "config_filename" } && $args{ "list_filename" } && $args{ "message" } ) {
        pod2usage(
            -message    => "You must provide an XML config filename AND a list filename AND a message\n",
            -exitval    => 255,
            -output     => \*STDOUT,
            -verbose    => 1
        );
    }

    return \%args;
}


