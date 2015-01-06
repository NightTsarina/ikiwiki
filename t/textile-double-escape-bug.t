#!/usr/bin/perl

use warnings;
use strict;

use Test::More tests => 4;
use utf8;

BEGIN {
	use_ok('IkiWiki');
	use_ok('IkiWiki::Plugin::mdwn');
	use_ok('IkiWiki::Plugin::textile');
};

subtest 'Text::Textile apparently double-escapes HTML entities in hrefs' => sub {
	my $text = q{Gödel, Escher, Bach};
	my $text_ok = qr{G(?:ö|&ouml;|&#246;|&#x[fF]6;)del, Escher, Bach};
	my $href = q{https://en.wikipedia.org/wiki/Gödel,_Escher,_Bach};
	my $href_ok = qr{https://en\.wikipedia\.org/wiki/G(?:ö|&ouml;|&#246;|&#x[fF]6|%[cC]3%[bB]6)del,_Escher,_Bach};
	my $good = qr{<p><a href="$href_ok">$text_ok</a></p>};

	chomp(my $mdwn_html = IkiWiki::Plugin::mdwn::htmlize(
		content => qq{[$text]($href)},
	));
	like($mdwn_html, $good);

	chomp(my $txtl_html = IkiWiki::Plugin::textile::htmlize(
		content => qq{"$text":$href},
	));
	TODO: {
	local $TODO = "Text::Textile double-escapes the href";
	like($txtl_html, $good);
	unlike($txtl_html, qr{<p><a href="https://en\.wikipedia\.org/wiki/G&amp;ouml;del,_Escher,_Bach">G&ouml;del, Escher, Bach</a></p>}i);
	}
};
