#!/usr/bin/perl
use warnings;
use strict;
use Test::More 'no_plan';
use IkiWiki;

sub check_trail {
	my $file=shift;
	my $expected=shift;
	my $trailname=shift || qr/\w+/;
	my $blob=readfile("t/tmp/out/$file");
	my ($trailline)=$blob=~/^trail=$trailname\s+(.*)$/m;
	is($trailline, $expected, "expected $expected in $file");
}

sub check_no_trail {
	my $file=shift;
	my $trailname=shift;
	my $blob=readfile("t/tmp/out/$file");
	my ($trailline)=$blob=~/^trail=$trailname\s+(.*)$/m;
	$trailline="" unless defined $trailline;
	ok($trailline !~ /^trail=$trailname\s+/, "no $trailname in $file");
}

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
	'[[!trailitems pagenames="sorting/beginning sorting/middle sorting/end"]] ' .
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

check_trail("badger.html", "n=mushroom p=", "meme");
check_trail("badger.html", "n=mr_toad p=ratty", "wind_in_the_willows");

ok(! -f "t/tmp/out/moley.html");

check_trail("mr_toad.html", "n=ratty p=badger", "wind_in_the_willows");
check_no_trail("mr_toad.html", "meme");
# meta title is respected for pages that have one
$blob = readfile("t/tmp/out/mr_toad.html");
ok($blob =~ /">&lt; The Breezy Badger<\/a>/m);
# pagetitle for pages that don't
ok($blob =~ /">ratty &gt;<\/a>/m);

check_no_trail("ratty.html", "meme");
check_trail("ratty.html", "n=badger p=mr_toad", "wind_in_the_willows");

check_trail("mushroom.html", "n=snake p=badger", "meme");
check_no_trail("mushroom.html", "wind_in_the_willows");

check_trail("snake.html", "n= p=mushroom", "meme");
check_no_trail("snake.html", "wind_in_the_willows");

check_trail("self_referential.html", "n= p=", "self_referential");

check_trail("add/b.html", "n=add/d p=", "add");
check_trail("add/d.html", "n= p=add/b", "add");
ok(! -f "t/tmp/out/add/a.html");
ok(! -f "t/tmp/out/add/c.html");
ok(! -f "t/tmp/out/add/e.html");

check_trail("del/a.html", "n=del/b p=");
check_trail("del/b.html", "n=del/c p=del/a");
check_trail("del/c.html", "n=del/d p=del/b");
check_trail("del/d.html", "n=del/e p=del/c");
check_trail("del/e.html", "n= p=del/d");

check_trail("sorting/linked.html", "n=sorting/a/b p=");
check_trail("sorting/a/b.html", "n=sorting/a/c p=sorting/linked");
check_trail("sorting/a/c.html", "n=sorting/z/a p=sorting/a/b");
check_trail("sorting/z/a.html", "n=sorting/beginning p=sorting/a/c");
check_trail("sorting/beginning.html", "n=sorting/middle p=sorting/z/a");
check_trail("sorting/middle.html", "n=sorting/end p=sorting/beginning");
check_trail("sorting/end.html", "n=sorting/new p=sorting/middle");
check_trail("sorting/new.html", "n=sorting/old p=sorting/end");
check_trail("sorting/old.html", "n=sorting/ancient p=sorting/new");
check_trail("sorting/ancient.html", "n=sorting/linked2 p=sorting/old");
check_trail("sorting/linked2.html", "n= p=sorting/ancient");

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

check_trail("add/a.html", "n=add/b p=");
check_trail("add/b.html", "n=add/c p=add/a");
check_trail("add/c.html", "n=add/d p=add/b");
check_trail("add/d.html", "n=add/e p=add/c");
check_trail("add/e.html", "n= p=add/d");

check_trail("del/b.html", "n=del/d p=");
check_trail("del/d.html", "n= p=del/b");
ok(! -f "t/tmp/out/del/a.html");
ok(! -f "t/tmp/out/del/c.html");
ok(! -f "t/tmp/out/del/e.html");

check_trail("sorting/old.html", "n=sorting/new p=");
check_trail("sorting/new.html", "n=sorting/middle p=sorting/old");
check_trail("sorting/middle.html", "n=sorting/linked2 p=sorting/new");
check_trail("sorting/linked2.html", "n=sorting/linked p=sorting/middle");
check_trail("sorting/linked.html", "n=sorting/end p=sorting/linked2");
check_trail("sorting/end.html", "n=sorting/a/c p=sorting/linked");
check_trail("sorting/a/c.html", "n=sorting/beginning p=sorting/end");
check_trail("sorting/beginning.html", "n=sorting/a/b p=sorting/a/c");
check_trail("sorting/a/b.html", "n=sorting/ancient p=sorting/beginning");
check_trail("sorting/ancient.html", "n=sorting/z/a p=sorting/a/b");
check_trail("sorting/z/a.html", "n= p=sorting/ancient");

ok(! system("rm -rf t/tmp"));
