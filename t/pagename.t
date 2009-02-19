#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 6;

BEGIN { use_ok("IkiWiki"); }

# Used internally.
$IkiWiki::hooks{htmlize}{mdwn}{call}=sub {};

is(pagename("foo.mdwn"), "foo");
is(pagename("foo/bar.mdwn"), "foo/bar");

# bare files get the full filename as page name
is(pagename("foo.png"), "foo.png");
is(pagename("foo/bar.png"), "foo/bar.png");
is(pagename("foo"), "foo");
