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
writefile("add.mdwn", "t/tmp/in", '[[!trailitems pagenames="add/a add/b add/c add/d add/e"]]');
writefile("add/b.mdwn", "t/tmp/in", "b");
writefile("add/d.mdwn", "t/tmp/in", "d");
writefile("del.mdwn", "t/tmp/in", '[[!trailitems pages="del/*" sort=title]]');
writefile("del/a.mdwn", "t/tmp/in", "a");
writefile("del/b.mdwn", "t/tmp/in", "b");
writefile("del/c.mdwn", "t/tmp/in", "c");
writefile("del/d.mdwn", "t/tmp/in", "d");
writefile("del/e.mdwn", "t/tmp/in", "e");
writefile("self_referential.mdwn", "t/tmp/in", '[[!trailitems pagenames="self_referential" circular=yes]]');
writefile("sorting/linked.mdwn", "t/tmp/in", "linked");
writefile("sorting/a/b.mdwn", "t/tmp/in", "a/b");
writefile("sorting/a/c.mdwn", "t/tmp/in", "a/c");
writefile("sorting/z/a.mdwn", "t/tmp/in", "z/a");
writefile("sorting/beginning.mdwn", "t/tmp/in", "beginning");
writefile("sorting/middle.mdwn", "t/tmp/in", "middle");
writefile("sorting/end.mdwn", "t/tmp/in", "end");
writefile("sorting/new.mdwn", "t/tmp/in", "new");
writefile("sorting/old.mdwn", "t/tmp/in", "old");
writefile("sorting/ancient.mdwn", "t/tmp/in", "ancient");
# These three need to be in the appropriate age order
ok(utime(333333333, 333333333, "t/tmp/in/sorting/new.mdwn"));
ok(utime(222222222, 222222222, "t/tmp/in/sorting/old.mdwn"));
ok(utime(111111111, 111111111, "t/tmp/in/sorting/ancient.mdwn"));
writefile("sorting/linked2.mdwn", "t/tmp/in", "linked2");
# This initially uses the default sort order: age for the inline, and path
# for trailitems. We change it later.
writefile("sorting.mdwn", "t/tmp/in",
	'[[!traillink linked]] ' .
	'[[!trailitems pages="sorting/z/a or sorting/a/b or sorting/a/c"]] ' .
	'[[!trailitems pagenames="beginning middle end"]] ' .
	'[[!inline pages="sorting/old or sorting/ancient or sorting/new" trail="yes"]] ' .
	'[[!traillink linked2]]');

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
[[!trailoptions circular=yes sort=title]]
[[!trailitems pages="ratty or badger or mr_toad"]]
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

$blob = readfile("t/tmp/out/sorting/linked.html");
ok($blob =~ m{^trail=sorting n=sorting/a/b p=$}m);
$blob = readfile("t/tmp/out/sorting/a/b.html");
ok($blob =~ m{^trail=sorting n=sorting/a/c p=sorting/linked$}m);
$blob = readfile("t/tmp/out/sorting/a/c.html");
ok($blob =~ m{^trail=sorting n=sorting/z/a p=sorting/a/b$}m);
$blob = readfile("t/tmp/out/sorting/z/a.html");
ok($blob =~ m{^trail=sorting n=sorting/beginning p=sorting/a/c$}m);
$blob = readfile("t/tmp/out/sorting/beginning.html");
ok($blob =~ m{^trail=sorting n=sorting/middle p=sorting/z/a$}m);
$blob = readfile("t/tmp/out/sorting/middle.html");
ok($blob =~ m{^trail=sorting n=sorting/end p=sorting/beginning$}m);
$blob = readfile("t/tmp/out/sorting/end.html");
ok($blob =~ m{^trail=sorting n=sorting/new p=sorting/middle$}m);
$blob = readfile("t/tmp/out/sorting/new.html");
ok($blob =~ m{^trail=sorting n=sorting/old p=sorting/end$}m);
$blob = readfile("t/tmp/out/sorting/old.html");
ok($blob =~ m{^trail=sorting n=sorting/ancient p=sorting/new$}m);
$blob = readfile("t/tmp/out/sorting/ancient.html");
ok($blob =~ m{^trail=sorting n=sorting/linked2 p=sorting/old$}m);
$blob = readfile("t/tmp/out/sorting/linked2.html");
ok($blob =~ m{^trail=sorting n= p=sorting/ancient$}m);

# Make some changes and refresh

writefile("add/a.mdwn", "t/tmp/in", "a");
writefile("add/c.mdwn", "t/tmp/in", "c");
writefile("add/e.mdwn", "t/tmp/in", "e");
ok(unlink("t/tmp/in/del/a.mdwn"));
ok(unlink("t/tmp/in/del/c.mdwn"));
ok(unlink("t/tmp/in/del/e.mdwn"));

writefile("sorting.mdwn", "t/tmp/in",
	readfile("t/tmp/in/sorting.mdwn") .
	'[[!trailoptions sort="title" reverse="yes"]]'); 

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

$blob = readfile("t/tmp/out/sorting/old.html");
ok($blob =~ m{^trail=sorting n=sorting/new p=$}m);
$blob = readfile("t/tmp/out/sorting/new.html");
ok($blob =~ m{^trail=sorting n=sorting/middle p=sorting/old$}m);
$blob = readfile("t/tmp/out/sorting/middle.html");
ok($blob =~ m{^trail=sorting n=sorting/linked2 p=sorting/new$}m);
$blob = readfile("t/tmp/out/sorting/linked2.html");
ok($blob =~ m{^trail=sorting n=sorting/linked p=sorting/middle$}m);
$blob = readfile("t/tmp/out/sorting/linked.html");
ok($blob =~ m{^trail=sorting n=sorting/end p=sorting/linked2$}m);
$blob = readfile("t/tmp/out/sorting/end.html");
ok($blob =~ m{^trail=sorting n=sorting/a/c p=sorting/linked$}m);
$blob = readfile("t/tmp/out/sorting/a/c.html");
ok($blob =~ m{^trail=sorting n=sorting/beginning p=sorting/end$}m);
$blob = readfile("t/tmp/out/sorting/beginning.html");
ok($blob =~ m{^trail=sorting n=sorting/a/b p=sorting/a/c$}m);
$blob = readfile("t/tmp/out/sorting/a/b.html");
ok($blob =~ m{^trail=sorting n=sorting/ancient p=sorting/beginning$}m);
$blob = readfile("t/tmp/out/sorting/ancient.html");
ok($blob =~ m{^trail=sorting n=sorting/z/a p=sorting/a/b$}m);
$blob = readfile("t/tmp/out/sorting/z/a.html");
ok($blob =~ m{^trail=sorting n= p=sorting/ancient$}m);

ok(! system("rm -rf t/tmp"));
