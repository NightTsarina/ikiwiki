#!/usr/bin/perl

package IkiWiki::Setup::Yaml;

use warnings;
use strict;
use IkiWiki;
use Encode;

sub loaddump ($$) {
	my $class=shift;
	my $content=shift;

	eval q{use YAML::XS};
	die $@ if $@;
	IkiWiki::Setup::merge(Load(encode_utf8($content)));
}

sub gendump ($@) {
	my $class=shift;
	
	"# IkiWiki::Setup::Yaml - YAML formatted setup file",
	"#",
	(map { "# $_" } @_),
	"#",
	IkiWiki::Setup::commented_dump(\&dumpline, "")
}


sub dumpline ($$$$) {
	my $key=shift;
	my $value=shift;
	my $type=shift;
	my $prefix=shift;
	
	eval q{use YAML::XS};
	die $@ if $@;
	$YAML::XS::QuoteNumericStrings=0;

	my $dump=decode_utf8(Dump({$key => $value}));
	$dump=~s/^---\n//; # yaml header, we don't want
	chomp $dump;
	if (length $prefix) {
		$dump=join("\n", map { $prefix.$_ } split(/\n/, $dump));
	}
	return $dump;
}

1
