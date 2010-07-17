#!/usr/bin/perl
# Tests for bugs relating to conflicting files in the srcdir
use warnings;
use strict;
use Test::More tests => 48;

# setup
my $srcdir="t/tmp/src";
my $destdir="t/tmp/dest";
ok(! system("make -s ikiwiki.out"));

# runs ikiwiki to build test site
sub runiki {
	my $testdesc=shift;
	ok((! system("perl -I. ./ikiwiki.out -plugin txt -plugin rawhtml -underlaydir=underlays/basewiki -set underlaydirbase=underlays -templatedir=templates $srcdir $destdir @_")),
		$testdesc);
}
sub refreshiki {
	runiki(shift);
}
sub setupiki {
	ok(! system("rm -rf $srcdir/.ikiwiki $destdir"));
	runiki(shift, "--rebuild");
}
sub newsrcdir {
	ok(! system("rm -rf $srcdir $destdir"));
	ok(! system("mkdir -p $srcdir"));
}

# At one point, changing the extension of the source file of a page caused
# ikiwiki to fail.
newsrcdir();
ok(! system("touch $srcdir/foo.mdwn"));
setupiki("initial setup");
ok(! system("mv $srcdir/foo.mdwn $srcdir/foo.txt"));
refreshiki("changed extension of source file of page");
ok(! system("mv $srcdir/foo.txt $srcdir/foo.mdwn"));
refreshiki("changed extension of source file of page 2");

# Conflicting page sources is sorta undefined behavior,
# but should not crash ikiwiki.
# Added when refreshing
ok(! system("touch $srcdir/foo.txt"));
refreshiki("conflicting page sources in refresh");
# Present during setup
newsrcdir();
ok(! system("touch $srcdir/foo.mdwn"));
ok(! system("touch $srcdir/foo.txt"));
setupiki("conflicting page sources in setup");

# Changing a page file into a non-page could also cause ikiwiki to fail.
newsrcdir();
ok(! system("touch $srcdir/foo.mdwn"));
setupiki("initial setup");
ok(! system("mv $srcdir/foo.mdwn $srcdir/foo"));
refreshiki("page file turned into non-page");

# Changing a non-page file into a page could also cause ikiwiki to fail.
newsrcdir();
ok(! system("touch $srcdir/foo"));
setupiki("initial setup");
ok(! system("mv $srcdir/foo $srcdir/foo.mdwn"));
refreshiki("non-page file turned into page");

# What if a page renders to the same html file that a rawhtml file provides?
# Added when refreshing
newsrcdir();
ok(! system("touch $srcdir/foo.mdwn"));
setupiki("initial setup");
ok(! system("mkdir -p $srcdir/foo"));
ok(! system("touch $srcdir/foo/index.html"));
refreshiki("rawhtml file rendered same as existing page in refresh");
# Inverse added when refreshing
newsrcdir();
ok(! system("mkdir -p $srcdir/foo"));
ok(! system("touch $srcdir/foo/index.html"));
setupiki("initial setup");
ok(! system("touch $srcdir/foo.mdwn"));
refreshiki("page rendered same as existing rawhtml file in refresh");
# Present during setup
newsrcdir();
ok(! system("touch $srcdir/foo.mdwn"));
ok(! system("mkdir -p $srcdir/foo"));
ok(! system("touch $srcdir/foo/index.html"));
setupiki("rawhtml file rendered same as existing page in setup");

# cleanup
ok(! system("rm -rf t/tmp"));
