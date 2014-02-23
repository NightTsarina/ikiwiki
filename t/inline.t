#!/usr/bin/perl
use warnings;
use strict;
use Test::More;
use IkiWiki;

my $blob;

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
	'[[!inline pages="friends/*" postform=yes]]');
write_old_file("antagonists.mdwn",
	'[[!inline pages="antagonists/*"]]');
write_old_file("enemies.mdwn",
	'[[!inline pages="enemies/*" postform=no rootpage=enemies]]');
foreach my $page (qw(protagonists/shepard protagonists/link
		antagonists/saren antagonists/ganondorf
		friends/liara friends/midna
		enemies/benezia enemies/zant)) {
	write_old_file("$page.mdwn", "this page is *$page*");
}

ok(! system("make -s ikiwiki.out"));

my $command = "perl -I. ./ikiwiki.out -set usedirs=0 -plugin inline -url=http://example.com -cgiurl=http://example.com/ikiwiki.cgi -rss -atom -underlaydir=underlays/basewiki -set underlaydirbase=underlays -templatedir=templates t/tmp/in t/tmp/out -verbose";

ok(! system($command));

ok(! system("$command -refresh"));

$blob = readfile("t/tmp/out/protagonists.html");
like($blob, qr{Add a new post}, 'rootpage=yes gives postform');
like($blob, qr{<input type="hidden" name="from" value="protagonists/new"},
	'explicit rootpage is /protagonists/new');

$blob = readfile("t/tmp/out/friends.html");
like($blob, qr{Add a new post}, 'postform=yes forces postform');
like($blob, qr{<input type="hidden" name="from" value="friends"},
	'implicit rootpage is /friends');

$blob = readfile("t/tmp/out/antagonists.html");
unlike($blob, qr{Add a new post}, 'default is no postform');

$blob = readfile("t/tmp/out/enemies.html");
unlike($blob, qr{Add a new post}, 'postform=no forces no postform');

done_testing;
