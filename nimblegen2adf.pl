#!/usr/bin/env perl
#
# Script to convert Nimblegen NDF files to MAGE-TAB ADF format.
#
# Modified from Tim Rayner's original script (Microarray Informatics, EMBL-EBI 2008)
#
# $Id: nimblegen2adf.pl 25471 2014-05-19 14:25:23Z amytang $

use strict;
use warnings;

use Log::Log4perl qw(:easy);

# Format for log statements
Log::Log4perl->easy_init( { level => $INFO, layout => '%-5p - %m%n' } );

# MAIN

# Use unbuffered STDOUT.
$| = 1;

my $ndf = shift;

unless ( $ndf ) {

    print <<"USAGE";

Usage: $0 <NDF filename>

USAGE

    LOGDIE ("You did not specify path to the NDF file.");
}

open( my $input_fh, '<', $ndf )
    or LOGDIE("Cannot open NDF file \"$ndf\": $!");
open( my $output_fh, '>', "$ndf.adf" )
    or LOGDIE ("Cannot open output file \"$ndf.adf\": $!");

INFO ("Converting NDF $ndf");

my (%cannot_map);  # Keeping track of probe classes that we can't map
                   # and print warnings at the very end

INFO ("Printing column headings for the ADF table.");

my $hlist = print_column_headings ( $input_fh, $output_fh );

INFO ("Converting NDF information into MAGE-TAB ADF table.");
print_body( $input_fh, $output_fh, $hlist );

print "\n";

if (keys %cannot_map) {
    foreach my $cannot_map_class (keys %cannot_map) {
        WARN("No mapping for $cannot_map_class in ".$cannot_map{$cannot_map_class}." lines."); 
   } 
}

close( $input_fh )  or LOGIDE($!);
close( $output_fh ) or LOGDIE($!);


# SUBS


sub print_column_headings {

    my ( $input_fh, $output_fh ) = @_;

    my $hline = <$input_fh>;
    $hline =~ s/[\r\n]+$//g;  # remove blank lines
    my @hlist = split /\t/, $hline, -1;
    
    # NB. Order of the values output below needs to match this list.
    # What used to be converted to "Comment[PRODE_ID]" is now
    # "Reporter Database Entry [nimblegen_probe_id]" as we cannot
    # have Comment[xxx] columns in the ADF table.
    
    print $output_fh (join(
	"\t",
	'Block Column',
	'Block Row',
	'Column',
	'Row',
	'Reporter Name',
	'Reporter Sequence',
    'Reporter Database Entry [nimblegen_chromosome_coordinate]',
    'Reporter Database Entry [nimblegen_probe_id]',
	'Reporter Group [role]',
	'Control Type',
    ), "\n");

    return \@hlist;
}

sub print_body {

    my ( $input_fh, $output_fh, $hlist ) = @_;

    my $line_num = 1;
    while ( my $line = <$input_fh> ) {

	# Print a dot every 4000 lines to show activity.
	print STDOUT "." unless ( $line_num % 4000 );

	$line =~ s/[\r\n]+$//g;
	
	my @linelist = split /\t/, $line, -1;

	unless ( scalar @$hlist == scalar @linelist ) {
	    LOGDIE ( "Line length mismatch at line $line_num\n" );
	}

	my %linehash;
	@linehash{ @$hlist } = @linelist;

	my ( $role, $control_type )
	    = remap_probe_class( $linehash{"PROBE_CLASS"} );

	my ( $seqtype, $polymertype, $sequence )
	    = remap_probe_sequence( $linehash{"PROBE_SEQUENCE"} );
    
    # Maybe should make this into Reporter Database Entry [xxx] if we're phasing out comments?
	my $chr_position =
             $linehash{'SEQ_ID'} =~ /chr(\d+|X|Y)/i ? "$linehash{SEQ_ID} ($linehash{POSITION})"
	  : "";

	# This needs to match the order of the headers output above.
    
	my @output = (
	    1,
	    1,
	    $linehash{'X'},
	    $linehash{'Y'},
	    $linehash{'PROBE_DESIGN_ID'},
	    $sequence,
	    $chr_position,
	    $linehash{'PROBE_ID'},
	    $role,
	    $control_type,
	);
    
	print $output_fh (join( "\t", @output ), "\n");

	$line_num++;
    }

    return;
}

sub remap_probe_class {

    my ( $probe_class ) = @_;

    my %mapping = (
	'experimental'               => [ "experimental", "" ],
	'control:empty'              => [ "control", "array control empty"   ],
	'control:keepout'            => [ "control", "array control empty"   ],
	'control:reseq_qc:label'     => [ "control", "array control label"   ],
	'control:reseq_qc:synthesis' => [ "control", "array control design"  ],
	'synthesis'                  => [ "control", "array control design"  ],
	'control:sample_tracking:a'  => [ "control", "array control design"  ],
	'control:sample_tracking:b'  => [ "control", "ccontrol unknown type"  ],
	'encoded number'             => [ "control", "array control label"   ],
	'fiducial'                   => [ "control", "array control label"   ],
	'lod'                        => [ "control", "array control label"   ],
	'photometric'                => [ "control", "array control spike calibration"   ],
	'linker'                     => [ "control", "array control design"  ],
	'uniformity'                 => [ "control", "array control design"  ],
	'control'                    => [ "control", "array control design"  ],
	""                           => [ "control", "array control design"  ],
	);

    my ( $role, $control_type );
    
    if ( defined( $mapping{ lc $probe_class } ) ) {
        ( $role, $control_type ) = @{ $mapping{ lc $probe_class } };
    }
    else {
        $cannot_map{$probe_class}++;
        $role         = "control";
        $control_type = "array control design";
    }

    return ( $role, $control_type);
}

sub remap_probe_sequence {

    my ( $probe_sequence ) = @_;

    my ( $seqtype, $polymertype, $sequence );

    if ( $probe_sequence eq 'N' ) {
	$sequence    = "";
	$seqtype     = "";
	$polymertype = "";
    }
    else {
	$sequence    = $probe_sequence;
	$seqtype     = 'ss_oligo';
	$polymertype = 'DNA';
    }

    return ( $seqtype, $polymertype, $sequence );  # seqtype and polymertype are no longer printed out in converted ADF as they aren't in MAGE-TAB spec
}
