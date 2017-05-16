#!/usr/bin/perl
use warnings;
use strict;
use Test::More;
use Encode;

BEGIN { use_ok("IkiWiki"); }
BEGIN { use_ok("IkiWiki::Render"); }

%config=IkiWiki::defaultconfig();
$config{srcdir}=$config{destdir}="/dev/null";

my $installed = $ENV{INSTALLED_TESTS};

unless ($installed) {
	$config{templatedir} = "templates";
	$config{underlaydir} = "underlays/basewiki";
	$config{underlaydirbase} = "underlays";
}

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

foreach my $scrub (0, 1) {
	if ($scrub) {
		$config{add_plugins}=[qw(color htmlscrubber toc)];
	}
	else {
		$config{add_plugins}=[qw(color toc)];
	}

	IkiWiki::loadplugins();
	IkiWiki::checkconfig();

	like(render('[[!color foreground="fuchsia" background="lime" text="Alert"]]'),
		qr{(?s)<span class="color" style="color: fuchsia; background-color: lime">Alert</span>});
	like(render('[[!color foreground="#336699" text="Hello"]]'),
		qr{(?s)<span class="color" style="color: \#336699">Hello</span>});
	like(render('[[!color background="#123" text="[Over there](http://localhost/)"]]'),
		qr{(?s)<span class="color" style="background-color: \#123"><a href="http://localhost/">Over there</a></span>});
	like(render('[[!color background="censored()" text="Hi"]]'),
		qr{(?s)<span class="color" style="">Hi</span>});
	like(render('[[!color foreground="x; pwned: exploit" text="Hi"]]'),
		qr{(?s)<span class="color" style="">Hi</span>});

	like(render("[[!toc ]]\n\n## [[!color foreground=red text=Important]]"),
		qr{<a href="\#index1h2">Important</a>});
}

done_testing();
