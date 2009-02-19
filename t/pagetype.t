#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 6;

BEGIN { use_ok("IkiWiki"); }

# Used internally.
$IkiWiki::hooks{htmlize}{mdwn}={};

is(pagetype("foo.mdwn"), "mdwn");
is(pagetype("foo/bar.mdwn"), "mdwn");
is(pagetype("foo.png"), undef);
is(pagetype("foo/bar.png"), undef);
is(pagetype("foo"), undef);
