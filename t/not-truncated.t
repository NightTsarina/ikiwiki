#!/usr/bin/perl
# Regression test for a weird build issue where wikitext.pm was installed
# as an empty file, possibly caused by parallel builds. This was hopefully
# fixed by making the build steps more robust in 3.20180228.
# https://buildd.debian.org/status/fetch.php?pkg=ikiwiki&arch=all&ver=3.20180105-1&stamp=1515285462&raw=0
# -rw-r--r-- root/root         0 2018-01-06 23:20 ./usr/share/perl5/IkiWiki/Plugin/wikitext.pm
use warnings;
use strict;
use Test::More;

my @libs="IkiWiki.pm";
push @libs, map { chomp; $_ } `find IkiWiki -type f -name \\*.pm`;

plan(tests => scalar @libs);

FILE: foreach my $file (@libs) {
	foreach my $libdir (@INC) {
		if (-e "$libdir/$file") {
			ok(-s "$libdir/$file", "$file available in $libdir and not truncated");
			next FILE;
		}
	}
	fail("$file not available in ".join(':', @INC));
}
