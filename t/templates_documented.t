#!/usr/bin/perl
use warnings;
use strict;
use Test::More;

plan(skip_all => 'running installed') if $ENV{INSTALLED_TESTS};

$/=undef;
open(IN, "doc/templates.mdwn") || die "doc/templates.mdwn: $!";
my $page=<IN>;
close IN;

foreach my $file (glob("templates/*.tmpl")) {
	$file=~s/templates\///;
	ok($page =~ /\Q$file\E/, "$file documented on doc/templates.mdwn");
}

done_testing();
