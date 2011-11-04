#!/usr/bin/perl
use warnings;
use strict;
use Test::More 'no_plan';
use IkiWiki;

my $blob;

ok(! system("rm -rf t/tmp"));
ok(! system("mkdir t/tmp"));

# Use a rather stylized template to override the default rendering, to make
# it easy to search for the desired results
writefile("templates/trails.tmpl", "t/tmp/in", <<EOF
<TMPL_LOOP TRAILLOOP>
<TMPL_IF __FIRST__><nav></TMPL_IF>
<div>
trail=<TMPL_VAR TRAILPAGE> n=<TMPL_VAR NEXTPAGE> p=<TMPL_VAR PREVPAGE>
</div>
<div>
<TMPL_IF PREVURL>
<a href="<TMPL_VAR PREVURL>">&lt; <TMPL_VAR PREVTITLE></a>
</TMPL_IF> |
<a href="<TMPL_VAR TRAILURL>">^ <TMPL_VAR TRAILTITLE> ^</a>
| <TMPL_IF NEXTURL>
<a href="<TMPL_VAR NEXTURL>"><TMPL_VAR NEXTTITLE> &gt;</a>
</TMPL_IF>
</div>
<TMPL_IF __LAST__></nav></TMPL_IF>
</TMPL_LOOP>
EOF
);
writefile("badger.mdwn", "t/tmp/in", "[[!meta title=\"The Breezy Badger\"]]\ncontent of badger");
writefile("mushroom.mdwn", "t/tmp/in", "content of mushroom");
writefile("snake.mdwn", "t/tmp/in", "content of snake");
writefile("ratty.mdwn", "t/tmp/in", "content of ratty");
writefile("mr_toad.mdwn", "t/tmp/in", "content of mr toad");
writefile("add.mdwn", "t/tmp/in", '[[!trail pagenames="add/a add/b add/c add/d add/e"]]');
writefile("add/b.mdwn", "t/tmp/in", "b");
writefile("add/d.mdwn", "t/tmp/in", "d");
writefile("del.mdwn", "t/tmp/in", '[[!trail pages="del/*" sort=title]]');
writefile("del/a.mdwn", "t/tmp/in", "a");
writefile("del/b.mdwn", "t/tmp/in", "b");
writefile("del/c.mdwn", "t/tmp/in", "c");
writefile("del/d.mdwn", "t/tmp/in", "d");
writefile("del/e.mdwn", "t/tmp/in", "e");
writefile("self_referential.mdwn", "t/tmp/in", '[[!trail pagenames="self_referential" circular=yes]]');

writefile("meme.mdwn", "t/tmp/in", <<EOF
[[!trail]]
* [[!traillink badger]]
* [[!traillink badger text="This is a link to badger, with a title"]]
* [[!traillink That_is_the_badger|badger]]
* [[!traillink badger]]
* [[!traillink mushroom]]
* [[!traillink mushroom]]
* [[!traillink snake]]
* [[!traillink snake]]
EOF
);

writefile("wind_in_the_willows.mdwn", "t/tmp/in", <<EOF
[[!trail circular=yes sort=title pages="ratty or badger or mr_toad"]]
[[!trailitem moley]]
EOF
);

ok(! system("make -s ikiwiki.out"));

my $command = "perl -I. ./ikiwiki.out -set usedirs=0 -plugin trail -plugin inline -url=http://example.com -cgiurl=http://example.com/ikiwiki.cgi -rss -atom -underlaydir=underlays/basewiki -set underlaydirbase=underlays -templatedir=templates t/tmp/in t/tmp/out -verbose";

ok(! system($command));

ok(! system("$command -refresh"));

$blob = readfile("t/tmp/out/meme.html");
ok($blob =~ /<a href="(\.\/)?badger.html">badger<\/a>/m);
ok($blob =~ /<a href="(\.\/)?badger.html">This is a link to badger, with a title<\/a>/m);
ok($blob =~ /<a href="(\.\/)?badger.html">That is the badger<\/a>/m);

$blob = readfile("t/tmp/out/badger.html");
ok($blob =~ /^trail=meme n=mushroom p=$/m);
ok($blob =~ /^trail=wind_in_the_willows n=mr_toad p=ratty$/m);

ok(! -f "t/tmp/out/moley.html");

$blob = readfile("t/tmp/out/mr_toad.html");
ok($blob !~ /^trail=meme/m);
ok($blob =~ /^trail=wind_in_the_willows n=ratty p=badger$/m);
# meta title is respected for pages that have one
ok($blob =~ /">&lt; The Breezy Badger<\/a>/m);
# pagetitle for pages that don't
ok($blob =~ /">ratty &gt;<\/a>/m);

$blob = readfile("t/tmp/out/ratty.html");
ok($blob !~ /^trail=meme/m);
ok($blob =~ /^trail=wind_in_the_willows n=badger p=mr_toad$/m);

$blob = readfile("t/tmp/out/mushroom.html");
ok($blob =~ /^trail=meme n=snake p=badger$/m);
ok($blob !~ /^trail=wind_in_the_willows/m);

$blob = readfile("t/tmp/out/snake.html");
ok($blob =~ /^trail=meme n= p=mushroom$/m);
ok($blob !~ /^trail=wind_in_the_willows/m);

$blob = readfile("t/tmp/out/self_referential.html");
ok($blob =~ /^trail=self_referential n= p=$/m);

$blob = readfile("t/tmp/out/add/b.html");
ok($blob =~ /^trail=add n=add\/d p=$/m);
$blob = readfile("t/tmp/out/add/d.html");
ok($blob =~ /^trail=add n= p=add\/b$/m);
ok(! -f "t/tmp/out/add/a.html");
ok(! -f "t/tmp/out/add/c.html");
ok(! -f "t/tmp/out/add/e.html");

$blob = readfile("t/tmp/out/del/a.html");
ok($blob =~ /^trail=del n=del\/b p=$/m);
$blob = readfile("t/tmp/out/del/b.html");
ok($blob =~ /^trail=del n=del\/c p=del\/a$/m);
$blob = readfile("t/tmp/out/del/c.html");
ok($blob =~ /^trail=del n=del\/d p=del\/b$/m);
$blob = readfile("t/tmp/out/del/d.html");
ok($blob =~ /^trail=del n=del\/e p=del\/c$/m);
$blob = readfile("t/tmp/out/del/e.html");
ok($blob =~ /^trail=del n= p=del\/d$/m);

# Make some changes and refresh

writefile("add/a.mdwn", "t/tmp/in", "a");
writefile("add/c.mdwn", "t/tmp/in", "c");
writefile("add/e.mdwn", "t/tmp/in", "e");
ok(unlink("t/tmp/in/del/a.mdwn"));
ok(unlink("t/tmp/in/del/c.mdwn"));
ok(unlink("t/tmp/in/del/e.mdwn"));

ok(! system("$command -refresh"));

$blob = readfile("t/tmp/out/add/a.html");
ok($blob =~ /^trail=add n=add\/b p=$/m);
$blob = readfile("t/tmp/out/add/b.html");
ok($blob =~ /^trail=add n=add\/c p=add\/a$/m);
$blob = readfile("t/tmp/out/add/c.html");
ok($blob =~ /^trail=add n=add\/d p=add\/b$/m);
$blob = readfile("t/tmp/out/add/d.html");
ok($blob =~ /^trail=add n=add\/e p=add\/c$/m);
$blob = readfile("t/tmp/out/add/e.html");
ok($blob =~ /^trail=add n= p=add\/d$/m);

$blob = readfile("t/tmp/out/del/b.html");
ok($blob =~ /^trail=del n=del\/d p=$/m);
$blob = readfile("t/tmp/out/del/d.html");
ok($blob =~ /^trail=del n= p=del\/b$/m);
ok(! -f "t/tmp/out/del/a.html");
ok(! -f "t/tmp/out/del/c.html");
ok(! -f "t/tmp/out/del/e.html");

#ok(! system("rm -rf t/tmp"));
