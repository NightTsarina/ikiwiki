#!/usr/bin/perl
use warnings;
use strict;

BEGIN {
	if (system("python -c 'import docutils.core'") != 0) {
		eval 'use Test::More skip_all => "docutils not available"';
	}
}

use Test::More tests => 2;

BEGIN { use_ok("IkiWiki"); }

%config=IkiWiki::defaultconfig();
$config{srcdir}=$config{destdir}="/dev/null";
$config{libdir}=".";
$config{add_plugins}=[qw(rst)];
IkiWiki::loadplugins();
IkiWiki::checkconfig();

ok(IkiWiki::htmlize("foo", "foo", "rst", "foo\n") =~ m{\s*<p>foo</p>\s*});
