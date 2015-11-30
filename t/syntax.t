#!/usr/bin/perl
use warnings;
use strict;
use Test::More;

plan(skip_all => 'running installed') if $ENV{INSTALLED_TESTS};

my @progs="ikiwiki.in";
my @libs="IkiWiki.pm";
# monotone, external, amazon_s3, po, and cvs
# skipped since they need perl modules
push @libs, map { chomp; $_ } `find IkiWiki -type f -name \\*.pm | grep -v monotone.pm | grep -v external.pm | grep -v amazon_s3.pm | grep -v po.pm | grep -v cvs.pm`;
push @libs, 'IkiWiki/Plugin/skeleton.pm.example';

plan(tests => (@progs + @libs));

foreach my $file (@progs) {
        ok(system("perl -c $file >/dev/null 2>&1") eq 0, $file);
}
foreach my $file (@libs) {
        ok(system("perl -c $file >/dev/null 2>&1") eq 0, $file);
}
