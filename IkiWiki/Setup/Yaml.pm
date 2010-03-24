#!/usr/bin/perl

package IkiWiki::Setup::Yaml;

use warnings;
use strict;
use IkiWiki;

sub loaddump ($$) {
	my $class=shift;
	my $content=shift;

	eval q{use YAML::Any};
	eval q{use YAML} if $@;
	die $@ if $@;
	$YAML::Syck::ImplicitUnicode=1;
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
	
	eval q{use YAML::Old};
	eval q{use YAML} if $@;
	die $@ if $@;
	$YAML::UseHeader=0;

	my $dump=Dump({$key => $value});
	chomp $dump;
	if (length $prefix) {
		$dump=join("\n", map { $prefix.$_ } split(/\n/, $dump));
	}
	return $dump;
}

1
