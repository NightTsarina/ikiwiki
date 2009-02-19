#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 6;

BEGIN { use_ok("IkiWiki"); }

# Used internally.
$IkiWiki::hooks{htmlize}{mdwn}=1;

is(pagetype("foo.mdwn"), "mdwn");
is(pagetype("foo/bar.mdwn"), "mdwn");

# bare files get the full filename as page name
is(pagename("foo.png"), "foo.png");
is(pagename("foo/bar.png"), "foo/bar.png");
is(pagename("foo"), "foo");
