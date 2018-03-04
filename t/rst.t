#!/usr/bin/perl
use warnings;
use strict;

BEGIN {
	if (system("python3 -c 'import docutils.core'") != 0) {
		eval 'use Test::More skip_all => "docutils not available"';
	}
}

use Test::More tests => 3;

BEGIN { use_ok("IkiWiki"); }

%config=IkiWiki::defaultconfig();
$config{srcdir}=$config{destdir}="/dev/null";
$config{libdir}=".";
$config{add_plugins}=[qw(rst)];
IkiWiki::loadplugins();
IkiWiki::checkconfig();

like(IkiWiki::htmlize("foo", "foo", "rst", "foo\n"), qr{\s*<p>foo</p>\s*});
# regression test for [[bugs/rst fails on file containing only a number]]
my $html = IkiWiki::htmlize("foo", "foo", "rst", "11");
$html =~ s/<[^>]*>//g;
like($html, qr{\s*11\s*});
