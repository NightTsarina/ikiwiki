#!/usr/bin/perl
# Standard ikiwiki setup module.
# Parameters to import should be all the standard ikiwiki config stuff.

package IkiWiki::Setup::Standard;

use warnings;
use strict;
use IkiWiki;

sub import {
	IkiWiki::Setup::merge($_[1]);
}

sub gendump ($$) {
	my $class=shift;
	my $description=shift;

	"#!/usr/bin/perl",
	"# $description",
	"#",
	"# Passing this to ikiwiki --setup will make ikiwiki generate",
	"# wrappers and build the wiki.",
	"#",
	"# Remember to re-run ikiwiki --setup any time you edit this file.",
	"use IkiWiki::Setup::Standard {",
	IkiWiki::Setup::commented_dump(\&dumpline),
	"}";
}

sub dumpline ($$$$) {
	my $key=shift;
	my $value=shift;
	my $type=shift;
	my $prefix=shift;
	
	eval q{use Data::Dumper};
	error($@) if $@;
	local $Data::Dumper::Terse=1;
	local $Data::Dumper::Indent=1;
	local $Data::Dumper::Pad="\t";
	local $Data::Dumper::Sortkeys=1;
	local $Data::Dumper::Quotekeys=0;
	# only the perl version preserves utf-8 in output
	local $Data::Dumper::Useperl=1;
	
	my $dumpedvalue;
	if (($type eq 'boolean' || $type eq 'integer') && $value=~/^[0-9]+$/) {
		# avoid quotes
		$dumpedvalue=$value;
	}
	elsif (ref $value eq 'ARRAY' && @$value && ! grep { /[^\S]/ } @$value) {
		# dump simple array as qw{}
		$dumpedvalue="[qw{".join(" ", @$value)."}]";
	}
	else {
		$dumpedvalue=Dumper($value);
		chomp $dumpedvalue;
		if (length $prefix) {
			# add to second and subsequent lines
			my @lines=split(/\n/, $dumpedvalue);
			$dumpedvalue="";
			for (my $x=0; $x <= $#lines; $x++) {
				$lines[$x] =~ s/^\t//;
				$dumpedvalue.="\t".($x ? $prefix : "").$lines[$x]."\n";
			}
		}
		$dumpedvalue=~s/^\t//;
		chomp $dumpedvalue;
	}
	
	return "\t$prefix$key => $dumpedvalue,";
}

1
