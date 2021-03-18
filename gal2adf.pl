#!/usr/bin/env perl
#
# gal2adf.pl
#
# A script to convert microarray spotter output files into
# MetaColumn-MetaRow format suitable for use with MIAMExpress. NOTE
# that the output of this script is not a fully-fledged ADF, as more
# annotation will typically be required. See
# http://www.ebi.ac.uk/miamexpress/help/adf/index.html for more
# information.
#
# Script originally created by Philippe Rocca-Serra 2003. Maintained
# by Tim Rayner as of Nov 2004; ArrayExpress Team, EBI.
#
# $Id: gal2adf.pl 1881 2008-01-10 10:13:43Z tfrayner $

use strict;
use warnings;

use Getopt::Long;

########
# SUBS #
########

sub get_input_filehandle {

    my ($infile, $error_fh) = @_;

    my $fh;

    open( $fh, '<', $infile ) or do {
	print $error_fh ("Error: Cannot open input file $infile: $!\n");
	return 0;
    };
    return $fh;
}

sub process_file {

    my ( $args ) = @_;

    # Once the error log is open all errors go to it
    my $error_fh;
    if ( $args->{errorfile} ) {
        open( $error_fh, '>', $args->{errorfile} )
            or die("Error: Cannot open error log file $args->{errorfile}: $!\n");
    }
    else { $error_fh = \*STDERR; }

    my $warning_fh;
    if ( $args->{warningfile} ) {
        open( $warning_fh, '>', $args->{warningfile} ) or do {
            print $error_fh (
                "Error: Cannot open warning log file $args->{warningfile}: $!\n");
            return 0;
        };
    }
    else { $warning_fh = \*STDERR; }

    my $fh = get_input_filehandle( $args->{infile}, $error_fh )
        or return 0;

    open( my $adf_fh, '>', $args->{adffile} ) or do {
        print $error_fh ("Error: Cannot open ADF output $args->{adffile}: $!\n");
        return 0;
    };
    my $dbid_fh;
    if ($args->{dbidfile}) {
        open( $dbid_fh, '>', $args->{dbidfile} ) or do {
            print $error_fh (
                "Error: Cannot open DBID output $args->{dbidfile}: $!\n");
            return 0;
        };
    }

    my $line;
    unless ( defined( $line = <$fh> ) ) {
        print $error_fh ("Error: Unable to read input file.\n");
        return 0;
    }
    seek( $fh, 0, 0 ) or do {
        print $error_fh ("Error: Unable to rewind input file.\n");
        return 0;
    };

    FILEFORMAT: {

        ( $line =~ m/^ATF/ ) && do {
	    Axon(
		 $fh,
		 $args->{dbidcol},
		 $adf_fh,
		 $dbid_fh,
		 $error_fh,
		 $warning_fh,
                ) or return 0;
	    last FILEFORMAT;
        };

        ( $line =~ m/^Virtek/ ) && do {
            $args->{dbidcol} = 6;
	    Virtek(
		   $fh,
		   $args->{dbidcol},
		   $adf_fh,
		   $dbid_fh,
		   $error_fh,
		   $warning_fh,
                ) or return 0;
	    last FILEFORMAT;
        };

        ( $line =~ m/^\d+,\s*\d+,\s*\d+,\s*\d+,/ ) && do {
	    Gentac(
		   $fh,
		   $args->{dbidcol},
		   $adf_fh,
		   $dbid_fh,
		   $error_fh,
		   $warning_fh,
		  ) or return 0;
	    last FILEFORMAT;
        };

        # Otherwise unrecognized
        print $error_fh ("Error: Unknown file format.\n");
        return 0;
    }

    # Need to close file to flush output.
    unless ( close( $adf_fh ) ) {
	print $error_fh ("Error: Unable to close ADF output file.\n");
	return 0;
    }

}

sub Axon {

    # Subroutine for handling Axon Gal spotter output files:

    my ( $fh, $dbid_column, $adf_fh, $dbid_fh, $error_fh, $warning_fh ) = @_;

    # Looking for the number of Metagrid from the header

    # Note that $blocks[0] is never used, since block numbers start at 1
    my $Blocknum = 0;
    my @blocks;
    my $line = <$fh>;
    my $delim;

    # Read through to the last line of the header.
    HEADER_LINE:
    until ( ($delim) = ( $line =~ /Block ([\s,]*) (?:Column|Row)/ixms ) ) {
        $line = <$fh>;
        $line =~ s/\"//g;    # strip quotes
        next HEADER_LINE
          if ( ($Blocknum) = ( $line =~ /\A BlockCount= (\d+)/xms ) );

        # This is ugly, but it does the job:
        if (
            $line =~ m{\A Block (\d+)    # num
			\s*
			= [\s,]*
			([\d\.]+)         # X
			,?\s*
			([\d\.]+)         # Y
			,?\s*
			[\d\.]+
			,?\s*
			(\d+)             # num_columns
			,?\s*
			[\d\.]+
			,?\s*
			(\d+)             # num_rows
		    }ixms
          )
        {
            $blocks[$1]{num}         = $1;
            $blocks[$1]{X}           = $2;
            $blocks[$1]{Y}           = $3;
            $blocks[$1]{num_columns} = $4;
            $blocks[$1]{num_rows}    = $5;
        }

        # Attempt to catch a read-through into the coordinate section.
        last HEADER_LINE if ( $line =~ m{\A \d+ \t \d+ \t \d+ \t}xms );
    }

    # The current line should now be the Block Column Row header.
    my @headings = split /$delim/, $line, -1;
    my ( $block_col, $column_col, $row_col, @slice );

    HEADING:
    foreach my $index ( 0 .. $#headings ) {
        if ( $headings[$index] =~ /\A block  \z/ixms ) {
            $block_col = $index;
            next HEADING;
        }
        if ( $headings[$index] =~ /\A column \z/ixms ) {
            $column_col = $index;
            next HEADING;
        }
        if ( $headings[$index] =~ /\A  row   \z/ixms ) {
            $row_col = $index;
            next HEADING;
        }

        # If it's neither, keep the index in a slice for later.
        push( @slice, $index );
    }

    # The second column must have been identified for the rest of the
    # code to work.
    unless ( defined($block_col) && defined($column_col) && defined($row_col) )
    {
        print $error_fh ("Error: First line of coordinates not recognized.\n");
        return 0;
    }

    if ( $#blocks < 0 ) {
        print $error_fh (
                "Error: No block coordinates found in the file header."
              . " Please correct this and resubmit the file.\n" );
        return 0;
    }

    if ( $Blocknum && ( $#blocks != $Blocknum ) ) {
        print $warning_fh (
                "Warning: The number of blocks declared in the file header"
              . " ($#blocks) disagrees with the BlockCount number ($Blocknum,"
              . " also specified in the file header).\n" );
    }

    {
        my $newheader = "MetaColumn\tMetaRow\t";
        $newheader .=
          join( "\t", @headings[ $column_col, $row_col ], @headings[@slice] );
        $newheader =~ s/[\r\n]*$//;
        print $adf_fh "$newheader\n";    #creation of fields headers.
    }

    # Conversion from the blocks coordinates to MetaColumns and
    # Metarows referencing :

    # Construct a block -> MC/MR lookup table
    {
        my $last_max_x = 0;
        my $metacolumn = 0;
        my $metarow    = 1;
        for ( my $block_num = 1 ; $block_num <= $#blocks ; $block_num++ ) {

            if ( $blocks[$block_num]{X} < $last_max_x ) {
                $metarow++;
                $metacolumn = 0;
            }
            $metacolumn++;

            $blocks[$block_num]{metarow}    = $metarow;
            $blocks[$block_num]{metacolumn} = $metacolumn;

            $last_max_x = $blocks[$block_num]{X};
        }
    }

    # Counts the feature description lines, split on "tabulation" and
    # send every element in a table that will be sliced later to
    # generate new coordinates
    while ( my $line = <$fh> ) {

        $line =~ s/\"//g;        # strip quotes
        $line =~ s/[\r\n]*$//;
        my @larry = split /$delim/, $line, -1;
        my $newline;
        {
            no warnings qw(uninitialized);
            $newline = join( "\t",
                             $blocks[ $larry[$block_col] ]{metacolumn},
                             $blocks[ $larry[$block_col] ]{metarow},
                             @larry[ $column_col, $row_col ],
                             @larry[@slice] );
        }
        print $adf_fh "$newline\n";

        if ( $dbid_column && $dbid_fh ) {
            my $gene = $larry[ $dbid_column - 1 ] || q{};
            print $dbid_fh "$gene\n";
        }

        $blocks[ $larry[$block_col] ]{num_cells}++;
    }

    # Counting the actual spotted features per blocks: checking for
    # consistency between expected and actual features present on array.
    my $warning;
    foreach my $block (@blocks) {
        next unless $block->{num_cells};
        my $block_features = $block->{num_rows} * $block->{num_columns};
        if ( $block->{num_cells} != $block_features ) {
            $warning .=
                "Warning: The actual number of features in block $block->{num}"
              . " ($block->{num_cells}) disagrees with the number indicated in"
              . " the file header ($block_features).\n";
        }
    }
    if ($warning) {
        $warning .=
            "NOTE: The input file is missing some features, as listed above."
          . " This is reflected in the constructed ADF. Please ensure that all"
          . " the features listed in your experimental data files are"
          . " represented in the final ADF.\n";
        print $warning_fh ($warning);
    }
    return 1;
}

sub Gentac {

    my ( $fh, $dbid_column, $adf_fh, $dbid_fh, $error_fh, $warning_fh ) = @_;

    # Extracting information from the Gentac header:

    my $line = <$fh>;
    $line = <$fh>;
    my $num_blocks = ( split /,/, $line )[0];
    $line = <$fh>;
    my ( $block_rows, $block_cols ) = ( split /,/, $line )[ 0, 1 ];

    my $features_per_block = $block_rows * $block_cols;

    # Rebuilding lines according to the MIAME requirements:

    print $adf_fh "MetaColumn\tMetaRow\tColumn\tRow\tReporter Identifier\n";

    my @check;
    my $num_features;
    while ( my $line = <$fh> ) {
        $line =~ s/\"//g;        # strip quotes
        $line =~ s/[\r\n]*$//;

        my @larry = split /,/, $line, -1;
        my $newline = join "\t", @larry[ 2, 1, 5, 4, 9 ];

        print $adf_fh "$newline\n";

        if ( $dbid_column && $dbid_fh ) {
            my $gene = $larry[ $dbid_column - 1 ] || q{};
            print $dbid_fh "$gene\n";
        }

        $check[ $larry[2] ][ $larry[1] ]++;
        $num_features++;
    }

    # First control: comparing expected number of feature deduced by
    # number of blocks and calculated number of feature per block with
    # the actual number of rows in the feature table itself:

    my $expected_features = $features_per_block * $num_blocks;
    unless ( $num_features == $expected_features ) {
        print $warning_fh (
                  "Warning: The actual number of features in the file"
                . " ($num_features) disagrees with the number indicated in the file"
                . " header ($expected_features). The input file is probably missing"
                . " some features, and this is reflected in the constructed ADF."
                . " Please ensure that all the features listed in your experimental"
                . " data files are represented in the final ADF.\n" );
    }

    # Second control: location and accounting of actual number of
    # features per blocks:

    foreach my $metacolumn (@check) {
        foreach my $blockcount (@$metacolumn) {
            if ( $blockcount && $blockcount != $features_per_block ) {
                print $warning_fh (
                    "Warning: Different number of features ($blockcount) than"
                        . " expected from file header ($features_per_block) in at"
                        . " least one block. The input file is probably missing"
                        . " some features, and this is reflected in the constructed"
                        . " ADF. Please ensure that all the features listed in your"
                        . " experimental data files are represented in the final"
                        . " ADF.\n" );
            }
        }
    }
    return 1;
}

sub Virtek {

    my ( $fh, $dbid_column, $adf_fh, $dbid_fh, $error_fh, $warning_fh ) = @_;

    my ( $supergrid_rows, $supergrid_columns, $grid_rows, $grid_columns,
        $grids_per_supergrid, $features_per_block, @blocks, );

    # Header parsing
    HEADERLINE:
    while ( my $line = <$fh> ) {
        $line =~ s/\"//g;    # strip quotes

        last if ( $line =~ /^Name\s*(row|column)\s/ );

        # Supergrid count:
        ( $line =~ m!^Number of super grids:\((\d+),\s*(\d+)\)!i )
            && do {
            ( $supergrid_rows, $supergrid_columns ) = ( $1, $2 );
            next;
            };

        # Counting grid within a SuperGrid:
        ( $line =~ m!^Number of grids:\((\d+),\s*(\d+)\)! )
            && do {
            ( $grid_rows, $grid_columns ) = ( $1, $2 );
            $grids_per_supergrid = ( $1 * $2 );
            next;
            };

        # counting spots within a grid:
        ( $line =~ m!^Dots per grid:\((\d+),\s*(\d+)\)! )
            && do {
            $features_per_block = ( $1 * $2 );
            next;
            };

        # searching and extracting grid coordinates
        ( $line
                =~ m!^Grid(\d+)\s*-\s*\[\((\d+),\s*(\d+)\)\s*-\s*\((\d+),\s*(\d+)\)\]!
            )
            && do {
            $blocks[$1]{num}              = $1;
            $blocks[$1]{supergrid_rownum} = $2;
            $blocks[$1]{supergrid_colnum} = $3;
            $blocks[$1]{grid_rownum}      = $4;
            $blocks[$1]{grid_colnum}      = $5;
            next;
            };
    }

    # Converting Grid referencing to MetaColumn-MetaRow referencing:

    foreach my $block (@blocks) {
        next unless $block->{num};
        $block->{X} = $block->{grid_colnum}
            + ( $grid_columns * ( $block->{supergrid_colnum} - 1 ) );
        $block->{Y} = $block->{grid_rownum}
            + ( $grid_rows * ( $block->{supergrid_rownum} - 1 ) );
    }

    # Converting input file into a controlled, MIAME formatted file
    print $adf_fh "MetaColumn\tMetaRow\tColumn\tRow\tName\tID\n";

    my $num_features;
    while ( my $line = <$fh> ) {
        $line =~ s/\"//g;        # strip quotes
        $line =~ s/[\r\n]*$//;
        my ($grid) = ( $line =~ m/^Grid(\d+)\s/i );
        my @larry = split /\t/, $line, -1;

        foreach my $i ( 0 .. 6 ) { $larry[$i] ||= q{}; }

        my $newline = join( "\t",
            $blocks[$grid]{X}, $blocks[$grid]{Y}, @larry[ 2, 1, 5, 6 ] );
        print $adf_fh "$newline\n";

        if ( $dbid_column && $dbid_fh ) {
            my $gene = $larry[ $dbid_column - 1 ] || q{};
            print $dbid_fh "$gene\n";
        }

        $blocks[$grid]{num_cells}++;
        $num_features++;
    }

    # First control: performing the structure control by comparing
    # actual number of feature and real one: calculation of the expected
    # number of feature in a array:
    my $expected_features = $features_per_block * $#blocks;
    unless ( $num_features == $expected_features ) {
        print $warning_fh (
                  "Warning: The actual number of features in the file"
                . " ($num_features) disagrees with the number indicated"
                . " in the file header ($expected_features). Please correct"
                . " this and resubmit the file.\n" );
    }

    # Counting the actual spotted features per blocks: checking for
    # consistency between expected and actual features present on array.
    my $warning;
    foreach my $block (@blocks) {
        if ( $block->{num} && $block->{num_cells} != $features_per_block ) {
            $warning .= "Warning: The actual number of features in block"
                . " $block->{num} ($block->{num_cells}) disagrees with the"
                . " number indicated in the file header"
                . " ($features_per_block). Please correct this and resubmit"
                . " the file.\n";
        }
    }
    if ($warning) {
        $warning .= "NOTE: The input file is missing some features, as listed"
            . " above. This is reflected in the constructed ADF. Please"
            . " ensure that all the features listed in your experimental"
            . " data files are represented in the final ADF.\n";
        print $warning_fh ($warning);
    }

    return 1;
}

########
# MAIN #
########

my ( $args, $wanthelp );

GetOptions(
    "i|input=s"   => \$args->{infile},
    "c|col=i"     => \$args->{dbidcol},
    "a|adf=s"     => \$args->{adffile},
    "d|dbid=s"    => \$args->{dbidfile},
    "e|error=s"   => \$args->{errorfile},
    "w|warning=s" => \$args->{warningfile},
    "h|help"      => \$wanthelp,
);

if ($wanthelp) {
    print <<HELPTEXT;

Usage: gal2adf.pl -i <input gal file> 

    The following optional arguments may also be used:

                  -a <output adf file> 

	          -c <column number containing database IDs>
                  -d <output database ID file>

                  -e <output error log file>
                  -w <output warning log file>

                  -h <this help text>

HELPTEXT

    exit;
}

unless ( $args->{infile} ) {
    print STDERR (
        "Error: Input file not specified. Please see gal2adf.pl -h for usage notes.\n"
    );
    exit;
}

my ( $namebase ) = ( $args->{infile} =~ /(.*?) (\.\w{3})? \z/xms );

$args->{dbidfile} ||= "${namebase}_dbid.txt" if $args->{dbidcol};
$args->{adffile}  ||= "${namebase}_adf.txt";

process_file( $args );

exit 0;
