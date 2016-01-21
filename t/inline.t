#!/usr/bin/perl
use warnings;
use strict;
use Test::More;
use IkiWiki;

my $installed = $ENV{INSTALLED_TESTS};

my @command;
if ($installed) {
	@command = qw(ikiwiki);
}
else {
	ok(! system("make -s ikiwiki.out"));
	@command = qw(perl -I. ./ikiwiki.out
		--underlaydir=underlays/basewiki
		--set underlaydirbase=underlays
		--templatedir=templates);
}

push @command, qw(--set usedirs=0 --plugin inline
	--url=http://example.com --cgiurl=http://example.com/ikiwiki.cgi
	--rss --atom t/tmp/in t/tmp/out --verbose);

my $blob;

my $add_new_post = gettext("Add a new post titled:");

ok(! system("rm -rf t/tmp"));
ok(! system("mkdir t/tmp"));

sub write_old_file {
	my $name = shift;
	my $content = shift;

	writefile($name, "t/tmp/in", $content);
	ok(utime(333333333, 333333333, "t/tmp/in/$name"));
}

write_old_file("protagonists.mdwn",
	'[[!inline pages="protagonists/*" rootpage="protagonists/new"]]');
write_old_file("friends.mdwn",
	'[[!inline pages="friends/*" postform=yes sort=title limit=2]]');
write_old_file("antagonists.mdwn",
	'[[!inline pages="antagonists/*"]]');
# using old spelling of "limit" ("show") to verify backwards compat
write_old_file("enemies.mdwn",
	'[[!inline pages="enemies/*" postform=no rootpage=enemies sort=title reverse=yes show=2]]');
# to test correct processing of ../
write_old_file("blah/blah/enemies.mdwn",
	'[[!inline pages="enemies/*" postform=no rootpage=enemies sort=title reverse=yes show=2]]');
foreach my $page (qw(protagonists/shepard protagonists/link
		antagonists/saren antagonists/ganondorf
		friends/garrus friends/liara friends/midna friends/telma
		enemies/benezia enemies/geth enemies/rachni
		enemies/zant)) {
	write_old_file("$page.mdwn", "this page is {$page}");
}
# test cross-linking between pages as rendered in RSS
write_old_file("enemies/zant.mdwn", "this page is {enemies/zant}\n\n".
	"Zant hates [[friends/Midna]].");

ok(! system(@command));
ok(! system(@command, "--refresh"));

$blob = readfile("t/tmp/out/protagonists.html");
like($blob, qr{\Q$add_new_post\E}, 'rootpage=yes gives postform');
like($blob, qr{<input type="hidden" name="from" value="protagonists/new"},
	'explicit rootpage is /protagonists/new');

$blob = readfile("t/tmp/out/friends.html");
like($blob, qr{\Q$add_new_post\E}, 'postform=yes forces postform');
like($blob, qr{<input type="hidden" name="from" value="friends"},
	'implicit rootpage is /friends');
like($blob, qr[this page is \{friends/garrus}.*this page is \{friends/liara}]s,
	'first two pages in desired sort order are present');
unlike($blob, qr{friends/(?:midna|telma)},
	'pages excluded by limit should not be present');

$blob = readfile("t/tmp/out/antagonists.html");
unlike($blob, qr{\Q$add_new_post\E}, 'default is no postform');

$blob = readfile("t/tmp/out/enemies.html");
unlike($blob, qr{\Q$add_new_post\E}, 'postform=no forces no postform');
like($blob, qr[this page is \{enemies/zant}.*this page is \{enemies/rachni}]s,
	'first two pages in reversed sort order are present');
unlike($blob, qr{enemies/(?:benezia|geth)},
	'pages excluded by show should not be present');

$blob = readfile("t/tmp/out/enemies.rss");
like($blob, qr[this page is \{enemies/zant}.*this page is \{enemies/rachni}]s,
	'first two pages in reversed sort order are present');
like($blob,
	qr[Zant hates &lt;a href=(?:['"]|&quot;)http://example\.com/friends/midna.html(?:['"]|&quot;)&gt;Midna&lt;/a&gt;]s,
	'link is correctly relative');

$blob = readfile("t/tmp/out/blah/blah/enemies.rss");
like($blob, qr[this page is \{enemies/zant}.*this page is \{enemies/rachni}]s,
	'first two pages in reversed sort order are present');
like($blob,
	qr[Zant hates &lt;a href=(?:['"]|&quot;)http://example\.com/friends/midna.html(?:['"]|&quot;)&gt;Midna&lt;/a&gt;]s,
	'link is correctly relative');

done_testing;
