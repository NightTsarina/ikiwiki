#!/usr/bin/perl
use warnings;
use strict;
use Test::More;
use Encode;

BEGIN { use_ok("IkiWiki"); }

%config=IkiWiki::defaultconfig();
$config{srcdir}=$config{destdir}="/dev/null";
IkiWiki::loadplugins();
IkiWiki::checkconfig();

is(IkiWiki::htmlize("foo", "foo", "mdwn",
	"C. S. Lewis wrote books\n"),
	"<p>C. S. Lewis wrote books</p>\n", "alphalist off by default");

$config{mdwn_alpha_lists} = 1;
like(IkiWiki::htmlize("foo", "foo", "mdwn",
	"A. One\n".
	"B. Two\n"),
	qr{<ol\W}, "alphalist can be enabled");

$config{mdwn_alpha_lists} = 0;
like(IkiWiki::htmlize("foo", "foo", "mdwn",
	"A. One\n".
	"B. Two\n"),
	qr{<p>A. One\sB. Two</p>\n}, "alphalist can be disabled");

like(IkiWiki::htmlize("foo", "foo", "mdwn",
	"This works[^1]\n\n[^1]: Sometimes it doesn't.\n"),
	qr{<p>This works<sup\W}, "footnotes on by default");

$config{mdwn_footnotes} = 0;
like(IkiWiki::htmlize("foo", "foo", "mdwn",
	"An unusual link label: [^1]\n\n[^1]: http://example.com/\n"),
	qr{<a href="http://example\.com/">\^1</a>}, "footnotes can be disabled");

$config{mdwn_footnotes} = 1;
like(IkiWiki::htmlize("foo", "foo", "mdwn",
	"This works[^1]\n\n[^1]: Sometimes it doesn't.\n"),
	qr{<p>This works<sup\W}, "footnotes can be enabled");

done_testing();
