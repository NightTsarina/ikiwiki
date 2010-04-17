#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 54;

BEGIN { use_ok("IkiWiki"); }

%config=IkiWiki::defaultconfig();

ok(IkiWiki::file_pruned("src/.htaccess", "src"));
ok(IkiWiki::file_pruned(".htaccess"));
ok(IkiWiki::file_pruned("src/.ikiwiki/", "src"));
ok(IkiWiki::file_pruned(".ikiwiki/"));
ok(IkiWiki::file_pruned("src/.ikiwiki/index", "src"));
ok(IkiWiki::file_pruned(".ikiwiki/index"));
ok(IkiWiki::file_pruned("src/CVS/foo", "src"));
ok(IkiWiki::file_pruned("CVS/foo"));
ok(IkiWiki::file_pruned("src/subdir/CVS/foo", "src"));
ok(IkiWiki::file_pruned("subdir/CVS/foo"));
ok(IkiWiki::file_pruned("src/.svn", "src"));
ok(IkiWiki::file_pruned(".svn"));
ok(IkiWiki::file_pruned("src/subdir/.svn", "src"));
ok(IkiWiki::file_pruned("subdir/.svn"));
ok(IkiWiki::file_pruned("src/subdir/.svn/foo", "src"));
ok(IkiWiki::file_pruned("subdir/.svn/foo"));
ok(IkiWiki::file_pruned("src/.git", "src"));
ok(IkiWiki::file_pruned(".git"));
ok(IkiWiki::file_pruned("src/subdir/.git", "src"));
ok(IkiWiki::file_pruned("subdir/.git"));
ok(IkiWiki::file_pruned("src/subdir/.git/foo", "src"));
ok(IkiWiki::file_pruned("subdir/.git/foo"));
ok(! IkiWiki::file_pruned("src/svn/fo", "src"));
ok(! IkiWiki::file_pruned("svn/fo"));
ok(! IkiWiki::file_pruned("src/git", "src"));
ok(! IkiWiki::file_pruned("git"));
ok(! IkiWiki::file_pruned("src/index.mdwn", "src"));
ok(! IkiWiki::file_pruned("index.mdwn"));
ok(! IkiWiki::file_pruned("src/index.", "src"));
ok(! IkiWiki::file_pruned("index."));

# these are ok because while the filename starts with ".", the canonpathed
# version does not
ok(! IkiWiki::file_pruned("src/.", "src"));
ok(! IkiWiki::file_pruned("src/./", "src"));
# OTOH, without a srcdir, no canonpath, so they're not allowed.
ok(IkiWiki::file_pruned("."));
ok(IkiWiki::file_pruned("./"));

# Without a srcdir, absolute filenames are not allowed.
ok(IkiWiki::file_pruned("/etc/passwd"));
ok(IkiWiki::file_pruned("//etc/passwd"));
ok(IkiWiki::file_pruned("/"));
ok(IkiWiki::file_pruned("//"));
ok(IkiWiki::file_pruned("///"));


ok(IkiWiki::file_pruned("src/..", "src"));
ok(IkiWiki::file_pruned(".."));
ok(IkiWiki::file_pruned("src/../", "src"));
ok(IkiWiki::file_pruned("../"));
ok(IkiWiki::file_pruned("src/../", "src"));
ok(IkiWiki::file_pruned("../"));

# This is perhaps counterintuitive.
ok(! IkiWiki::file_pruned("src", "src"));

# Dots, etc, in the srcdir are ok.
ok(! IkiWiki::file_pruned("/.foo/src", "/.foo/src"));
ok(IkiWiki::file_pruned("/.foo/src/.foo/src", "/.foo/src"));
ok(! IkiWiki::file_pruned("/.foo/src/index.mdwn", "/.foo/src/index.mdwn"));

ok(IkiWiki::file_pruned("src/y/foo.dpkg-tmp", "src"));
ok(IkiWiki::file_pruned("y/foo.dpkg-tmp"));
ok(IkiWiki::file_pruned("src/y/foo.ikiwiki-new", "src"));
ok(IkiWiki::file_pruned("y/foo.ikiwiki-new"));
