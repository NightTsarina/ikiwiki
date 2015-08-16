#!/usr/bin/perl
use warnings;
use strict;
use Test::More;
use IkiWiki;

my $tmp = 't/tmp';
my $srcdir = "$tmp/in";
my $destdir = "$tmp/out";

my @command = (qw(./ikiwiki.out --plugin meta --disable-plugin htmlscrubber));
push @command, qw(-underlaydir=underlays/basewiki);
push @command, qw(-set underlaydirbase=underlays);
push @command, qw(--templatedir=templates);
push @command, $srcdir, $destdir;

sub write_build_read_compare {
	my ($pagename, $input, $expected_output) = @_;
	ok(! system("mkdir -p $srcdir"), q{setup});
	writefile("$pagename.mdwn", $srcdir, $input);
	ok(! system(@command), q{build});
	like(readfile("$destdir/$pagename/index.html"), $expected_output);
	ok(! system("rm -rf $tmp"), q{teardown});
}

write_build_read_compare(
	'title',
	q{[[!meta title="a page about bar"]]},
	qr{<title>a page about bar</title>},
);

write_build_read_compare(
	'description',
	q{[[!meta description="a page about bar"]]},
	qr{<meta name="description" content="a page about bar" />},
);

write_build_read_compare(
	'guid',
	q{[[!meta guid="12345"]]},
	qr{<meta name="guid" content="12345" />},
);

write_build_read_compare(
	'license',
	q{[[!meta license="you get to keep both pieces"]]},
	qr{<div class="pagelicense">},
);

write_build_read_compare(
	'copyright',
	q{[[!meta copyright="12345"]]},
	qr{<div class="pagecopyright">},
);

write_build_read_compare(
	'enclosure',
	q{[[!meta enclosure="ikiwiki/login-selector/wordpress.png"]]},
	qr{<meta name="enclosure" content="/ikiwiki/login-selector/wordpress.png" />},
);

write_build_read_compare(
	'author',
	q{[[!meta author="Noodly J. Appendage"]]},
	qr{<meta name="author" content="Noodly J. Appendage" />},
);

write_build_read_compare(
	'authorurl',
	q{[[!meta authorurl="http://noodly.appendage"]]},
	qr{<meta name="authorurl" content="http://noodly.appendage" />},
);

write_build_read_compare(
	'permalink',
	q{[[!meta permalink="http://noodly.appendage"]]},
	qr{<link rel="bookmark" href="http://noodly.appendage" />},
);

write_build_read_compare(
	'date',
	q{[[!meta date="12345"]]},
	qr{<meta name="date" content="12345" />},
);

write_build_read_compare(
	'updated',
	q{[[!meta updated="12345"]]},
	qr{<meta name="updated" content="12345" />},
);

#write_build_read_compare(
#	'stylesheet',
#	q{[[!meta stylesheet="wonka.css"]]},
#	qr{<link href="wonka.css"},
#);

#write_build_read_compare(
#	'script',
#	q{[[!meta script="wonka.js"]]},
#	qr{<link href="wonka.js"},
#);

write_build_read_compare(
	'openid',
	q{[[!meta openid="wonka.openid.example"]]},
	qr{<link href="wonka\.openid\.example" rel="openid\.delegate" />},
);

write_build_read_compare(
	'foaf',
	q{[[!meta foaf="wonka.foaf.example"]]},
	qr{<link rel="meta" type="application/rdf\+xml" title="FOAF"},
);

write_build_read_compare(
	'redir',
	q{[[!meta redir="http://wonka.redir.example"]]},
	qr{<meta http-equiv="refresh" content="0; URL=http://wonka\.redir\.example" />},
);

#write_build_read_compare(
#	'link',
#	q{[[!meta link="http://wonka.link.example"]]},
#	qr{<link href="http://wonka\.link\.example" />},
#);

# XXX buggy? is this my bug? maybe twitter:foo would just work if this worked
#write_build_read_compare(
#	'name',
#	q{[[!meta name="thingy" value1="hi" value2="hello"]]},
#	qr{<meta name="thingy" value1="hi" value2="hello" />},
#);

write_build_read_compare(
	'keywords',
	q{[[!meta keywords="word1,word2,word3"]]},
	qr{<meta name="keywords" content="word1,word2,word3" />},
);

write_build_read_compare(
	'arbitrary',
	q{[[!meta moo="mooooo"]]},
	qr{<meta name="moo" content="mooooo" />},
);

#write_build_read_compare(
#	'twittercard1',
#	'[[!meta twitter:card="player"]]',
#	qr{<meta name="twitter:card" content="player" />},
#);
#
#write_build_read_compare(
#	'twittercard2',
#	'[[!meta name="twitter:card" content="player"]]',
#	qr{<meta name="twitter:card" content="player" />},
#);

done_testing();
