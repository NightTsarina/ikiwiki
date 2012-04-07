#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 6;
use File::Path qw(make_path remove_tree);

BEGIN { use_ok("IkiWiki"); }
BEGIN { use_ok("IkiWiki::Render"); }

%config=IkiWiki::defaultconfig();

remove_tree("t/tmp");

make_path("t/tmp/srcdir/a/b/c");
make_path("t/tmp/srcdir/d/e/f");
writefile("a/b/c/d.mdwn", "t/tmp/srcdir", "foo");
writefile("d/e/f/g.mdwn", "t/tmp/srcdir", "foo");
IkiWiki::prune("t/tmp/srcdir/d/e/f/g.mdwn");
ok(-d "t/tmp/srcdir");
ok(! -e "t/tmp/srcdir/d");
IkiWiki::prune("t/tmp/srcdir/a/b/c/d.mdwn", "t/tmp/srcdir");
ok(-d "t/tmp/srcdir");
ok(! -e "t/tmp/srcdir/a");
