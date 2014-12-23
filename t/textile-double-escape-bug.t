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
	my $href = q{https://en.wikipedia.org/wiki/Gödel,_Escher,_Bach};
	my $good = qq{<p><a href="$href">$text</a></p>};

	chomp(my $mdwn_html = IkiWiki::Plugin::mdwn::htmlize(
		content => qq{[$text]($href)},
	));
	is($mdwn_html, $good);

	chomp(my $txtl_html = IkiWiki::Plugin::textile::htmlize(
		content => qq{"$text":$href},
	));
	isnt($txtl_html, $good);
	is($txtl_html, q{<p><a href="https://en.wikipedia.org/wiki/G&amp;ouml;del,_Escher,_Bach">G&ouml;del, Escher, Bach</a></p>});
};
