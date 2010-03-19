#!/usr/bin/perl

package IkiWiki::Setup::Yaml;

use warnings;
use strict;
use IkiWiki;
use YAML;

sub loaddump ($$) {
	my $class=shift;
	my $content=shift;

	IkiWiki::Setup::merge(Load($content));
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
	
	$YAML::UseHeader=0;
	my $dump=Dump({$key => $value});
	chomp $dump;
	if (length $prefix) {
		$dump=join("", map { $prefix.$_ } split(/\n/, $dump));
	}
	return $dump;
}

1
