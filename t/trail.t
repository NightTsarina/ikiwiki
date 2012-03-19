#!/usr/bin/perl
use warnings;
use strict;
use Test::More 'no_plan';
use IkiWiki;

my $blob;

ok(! system("rm -rf t/tmp"));
ok(! system("mkdir t/tmp"));

# Write files with a date in the past, so that when we refresh,
# the update is detected.
sub write_old_file {
	my $name = shift;
	my $content = shift;

	writefile($name, "t/tmp/in", $content);
	ok(utime(333333333, 333333333, "t/tmp/in/$name"));
}

# Use a rather stylized template to override the default rendering, to make
# it easy to search for the desired results
write_old_file("templates/trails.tmpl", <<EOF
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
write_old_file("badger.mdwn", "[[!meta title=\"The Breezy Badger\"]]\ncontent of badger");
write_old_file("mushroom.mdwn", "content of mushroom");
write_old_file("snake.mdwn", "content of snake");
write_old_file("ratty.mdwn", "content of ratty");
write_old_file("mr_toad.mdwn", "content of mr toad");
write_old_file("add.mdwn", '[[!trailitems pagenames="add/a add/b add/c add/d add/e"]]');
write_old_file("add/b.mdwn", "b");
write_old_file("add/d.mdwn", "d");
write_old_file("del.mdwn", '[[!trailitems pages="del/*" sort=title]]');
write_old_file("del/a.mdwn", "a");
write_old_file("del/b.mdwn", "b");
write_old_file("del/c.mdwn", "c");
write_old_file("del/d.mdwn", "d");
write_old_file("del/e.mdwn", "e");
write_old_file("self_referential.mdwn", '[[!trailitems pagenames="self_referential" circular=yes]]');
write_old_file("sorting/linked.mdwn", "linked");
write_old_file("sorting/a/b.mdwn", "a/b");
write_old_file("sorting/a/c.mdwn", "a/c");
write_old_file("sorting/z/a.mdwn", "z/a");
write_old_file("sorting/beginning.mdwn", "beginning");
write_old_file("sorting/middle.mdwn", "middle");
write_old_file("sorting/end.mdwn", "end");
write_old_file("sorting/new.mdwn", "new");
write_old_file("sorting/old.mdwn", "old");
write_old_file("sorting/ancient.mdwn", "ancient");
# These three need to be in the appropriate age order
ok(utime(333333333, 333333333, "t/tmp/in/sorting/new.mdwn"));
ok(utime(222222222, 222222222, "t/tmp/in/sorting/old.mdwn"));
ok(utime(111111111, 111111111, "t/tmp/in/sorting/ancient.mdwn"));
write_old_file("sorting/linked2.mdwn", "linked2");
# This initially uses the default sort order: age for the inline, and path
# for trailitems. We change it later.
write_old_file("sorting.mdwn",
	'[[!traillink linked]] ' .
	'[[!trailitems pages="sorting/z/a or sorting/a/b or sorting/a/c"]] ' .
	'[[!trailitems pagenames="beginning middle end"]] ' .
	'[[!inline pages="sorting/old or sorting/ancient or sorting/new" trail="yes"]] ' .
	'[[!traillink linked2]]');

write_old_file("meme.mdwn", <<EOF
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

write_old_file("wind_in_the_willows.mdwn", <<EOF
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

# Make some changes and refresh. These writefile calls don't set an
# old mtime, so they're strictly newer than the "old" files.

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
