#!/usr/bin/perl
use warnings;
use strict;
use Test::More;
use Encode;

BEGIN { use_ok("IkiWiki"); }
BEGIN { use_ok("IkiWiki::Render"); }

%config=IkiWiki::defaultconfig();
$config{srcdir}=$config{destdir}="/dev/null";
$config{add_plugins}=[qw(toc)];

my $installed = $ENV{INSTALLED_TESTS};

unless ($installed) {
	$config{templatedir} = "templates";
	$config{underlaydir} = "underlays/basewiki";
	$config{underlaydirbase} = "underlays";
}

IkiWiki::loadplugins();
IkiWiki::checkconfig();

sub render {
	my $content = shift;
	$IkiWiki::pagesources{foo} = "foo.mdwn";
	$IkiWiki::pagemtime{foo} = 42;
	$IkiWiki::pagectime{foo} = 42;
	$content = IkiWiki::filter("foo", "foo", $content);
	$content = IkiWiki::preprocess("foo", "foo", $content);
	$content = IkiWiki::linkify("foo", "foo", $content);
	$content = IkiWiki::htmlize("foo", "foo", "mdwn", $content);
	$content = IkiWiki::genpage("foo", $content);
	return $content;
}

# https://ikiwiki.info/todo/toc-with-human-readable-anchors/
# (toc-recycle-id part)
like(render('[[!toc ]]
## Weasels

These mustelids are weasilly recognised

<h2 id="the-chapter-on-stoats">Stoats</h2>

These are stoatally different
'),
	qr{(?s)<a href="\#index1h2">.*<a href="\#the-chapter-on-stoats">});

done_testing();
