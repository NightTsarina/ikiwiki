#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 19;

BEGIN { use_ok("IkiWiki"); }

# define mdwn as an extension
$IkiWiki::hooks{htmlize}{mdwn}={};
is(pagetype("foo.mdwn"), "mdwn");
is(pagename("foo.mdwn"), "foo");
is(pagetype("foo/bar.mdwn"), "mdwn");
is(pagename("foo/bar.mdwn"), "foo/bar");

# bare files get the full filename as page name, undef type
is(pagetype("foo.png"), undef);
is(pagename("foo.png"), "foo.png");
is(pagetype("foo/bar.png"), undef);
is(pagename("foo/bar.png"), "foo/bar.png");
is(pagetype("foo"), undef);
is(pagename("foo"), "foo");

# keepextension preserves the extension in the page name
$IkiWiki::hooks{htmlize}{txt}={keepextension => 1};
is(pagename("foo.txt"), "foo.txt");
is(pagetype("foo.txt"), "txt");
is(pagename("foo/bar.txt"), "foo/bar.txt");
is(pagetype("foo/bar.txt"), "txt");

# noextension makes extensionless files be treated as first-class pages
$IkiWiki::hooks{htmlize}{Makefile}={noextension =>1};
is(pagetype("Makefile"), "Makefile");
is(pagename("Makefile"), "Makefile");
is(pagetype("foo/Makefile"), "Makefile");
is(pagename("foo/Makefile"), "foo/Makefile");
