#!/usr/bin/perl
use warnings;
use strict;
use Test::More 'no_plan';

# setup
my $srcdir="t/tmp/src";
my $destdir="t/tmp/dest";
ok(! system("make -s ikiwiki.out"));
ok(! system("mkdir -p $srcdir"));

# runs ikiwiki to build test site
sub runiki {
	ok(! system("perl -I. ./ikiwiki.out -plugin html -underlaydir=underlays/basewiki -set underlaydirbase=underlays -templatedir=templates $srcdir $destdir @_"));
}
sub refreshiki {
	runiki();
}
sub setupiki {
	ok(! system("rm -rf $srcdir/.ikiwiki $destdir"));
	runiki("--rebuild");
}

# At one point, changing the extension of the source file of a page caused
# ikiwiki to fail.
ok(! system("touch $srcdir/foo.mdwn"));
setupiki();
ok(! system("mv $srcdir/foo.mdwn $srcdir/foo.html"));
refreshiki();

# Changing a non-page file into a page could also cause ikiwiki to fail.

# cleanup
ok(! system("rm -rf t/tmp"));
