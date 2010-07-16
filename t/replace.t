#!/usr/bin/perl
# Tests for bugs relating to replacing/renaming files in the srcdir.
use warnings;
use strict;
use Test::More 'no_plan';

# setup
my $srcdir="t/tmp/src";
my $destdir="t/tmp/dest";
ok(! system("make -s ikiwiki.out"));

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
sub newsrcdir {
	ok(! system("rm -rf $srcdir $destdir"));
	ok(! system("mkdir -p $srcdir"));
}

# At one point, changing the extension of the source file of a page caused
# ikiwiki to fail.
newsrcdir();
ok(! system("touch $srcdir/foo.mdwn"));
setupiki();
ok(! system("mv $srcdir/foo.mdwn $srcdir/foo.html"));
refreshiki();
ok(! system("mv $srcdir/foo.html $srcdir/foo.mdwn"));
refreshiki();

# Changing a non-page file into a page could also cause ikiwiki to fail.
newsrcdir();
ok(! system("touch $srcdir/foo"));
setupiki();
ok(! system("mv $srcdir/foo $srcdir/foo.mdwn"));
refreshiki();

# Changing a page file into a non-page could also cause ikiwiki to fail.
newsrcdir();
ok(! system("touch $srcdir/foo.mdwn"));
setupiki();
ok(! system("mv $srcdir/foo.mdwn $srcdir/foo"));
refreshiki();

# cleanup
ok(! system("rm -rf t/tmp"));
