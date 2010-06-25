#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 27;

BEGIN { use_ok("IkiWiki"); }

%config=IkiWiki::defaultconfig();

ok(IkiWiki::file_pruned(".htaccess"));
ok(IkiWiki::file_pruned(".ikiwiki/"));
ok(IkiWiki::file_pruned(".ikiwiki/index"));
ok(IkiWiki::file_pruned("CVS/foo"));
ok(IkiWiki::file_pruned("subdir/CVS/foo"));
ok(IkiWiki::file_pruned(".svn"));
ok(IkiWiki::file_pruned("subdir/.svn"));
ok(IkiWiki::file_pruned("subdir/.svn/foo"));
ok(IkiWiki::file_pruned(".git"));
ok(IkiWiki::file_pruned("subdir/.git"));
ok(IkiWiki::file_pruned("subdir/.git/foo"));
ok(! IkiWiki::file_pruned("svn/fo"));
ok(! IkiWiki::file_pruned("git"));
ok(! IkiWiki::file_pruned("index.mdwn"));
ok(! IkiWiki::file_pruned("index."));
ok(IkiWiki::file_pruned("."));
ok(IkiWiki::file_pruned("./"));

# absolute filenames are not allowed.
ok(IkiWiki::file_pruned("/etc/passwd"));
ok(IkiWiki::file_pruned("//etc/passwd"));
ok(IkiWiki::file_pruned("/"));
ok(IkiWiki::file_pruned("//"));
ok(IkiWiki::file_pruned("///"));


ok(IkiWiki::file_pruned(".."));
ok(IkiWiki::file_pruned("../"));

ok(IkiWiki::file_pruned("y/foo.dpkg-tmp"));
ok(IkiWiki::file_pruned("y/foo.ikiwiki-new"));
