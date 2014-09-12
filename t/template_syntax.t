#!/usr/bin/perl
use warnings;
use strict;
use Test::More;

my @templates=(glob("templates/*.tmpl"), glob("doc/templates/*.mdwn"));
plan(tests => 2*@templates);

use HTML::Template;

foreach my $template (@templates) {
	my $obj=eval {HTML::Template->new(filename => $template)};
	ok(! $@, $template." $@");
	ok($obj, $template);
}
