#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 87;

BEGIN { use_ok("IkiWiki"); }

ok(pagespec_match("foo", "*"));
ok(!pagespec_match("foo", ""));
ok(pagespec_match("foo", "!bar"));
ok(pagespec_match("page", "?ag?"));
ok(! pagespec_match("page", "?a?g?"));
ok(pagespec_match("foo.png", "*.*"));
ok(! pagespec_match("foo", "*.*"));
ok(pagespec_match("foo", "foo or bar"), "simple list");
ok(pagespec_match("bar", "foo or bar"), "simple list 2");
ok(pagespec_match("foo", "f?? and !foz"));
ok(! pagespec_match("foo", "f?? and !foo"));
ok(! pagespec_match("foo", "* and !foo"));
ok(! pagespec_match("foo", "foo and !foo"));
ok(! pagespec_match("foo.png", "* and !*.*"));
ok(pagespec_match("foo", "(bar or ((meep and foo) or (baz or foo) or beep))"));
ok(pagespec_match("foo", "(
	bar
	or (
		(meep and foo)
		or
		(baz or foo)
		or beep
	)
)"), "multiline complex pagespec");
ok(! pagespec_match("a/foo", "foo", location => "a/b"), "nonrelative fail");
ok(! pagespec_match("foo", "./*", location => "a/b"), "relative fail");
ok(pagespec_match("a/foo", "./*", location => "a/b"), "relative");
ok(pagespec_match("a/b/foo", "./*", location => "a/b"), "relative 2");
ok(pagespec_match("a/foo", "./*", "a/b"), "relative oldstyle call");
ok(pagespec_match("foo", "./*", location => "a"), "relative toplevel");
ok(pagespec_match("foo/bar", "*", location => "baz"), "absolute");
ok(! pagespec_match("foo", "foo and bar"), "foo and bar");
ok(pagespec_match("{f}oo", "{*}*"), "curly match");
ok(! pagespec_match("foo", "{*}*"), "curly !match");

ok(pagespec_match("somepage", "user(frodo)", user => "frodo"));
ok(pagespec_match("somepage", "user(frodo)", user => "Frodo"));
ok(! pagespec_match("somepage", "user(frodo)", user => "Sam"));
ok(pagespec_match("somepage", "user(*o)", user => "Bilbo"));
ok(pagespec_match("somepage", "user(*o)", user => "frodo"));
ok(! pagespec_match("somepage", "user(*o)", user => "Sam"));
ok(pagespec_match("somepage", "user(http://*.myopenid.com/)", user => "http://foo.myopenid.com/"));
ok(pagespec_match("somepage", "user(*://*)", user => "http://foo.myopenid.com/"));

# The link and backlink stuff needs this.
$config{userdir}="";
$links{foo}=[qw{bar baz}];
$links{bar}=[];
$links{baz}=[];
$links{meh}=[];
$links{"bugs/foo"}=[qw{bugs/done}];
$links{"bugs/done"}=[];
$links{"bugs/bar"}=[qw{done}];
$links{"done"}=[];
$links{"done"}=[];
$links{"examples/softwaresite/bugs/fails_to_frobnicate"}=[qw{done}];
$links{"examples/softwaresite/bugs/done"}=[];
$links{"ook"}=[qw{/blog/tags/foo}];
foreach my $p (keys %links) {
	$pagesources{$p}="$p.mdwn";
}
$pagesources{"foo.png"}="foo.png";
$pagesources{"foo"}="foo.mdwn";
$IkiWiki::hooks{htmlize}{mdwn}={};

ok(pagespec_match("foo", "foo"), "simple");
ok(! pagespec_match("foo", "bar"), "simple fail");
ok(pagespec_match("foo", "foo"), "simple glob");
ok(pagespec_match("foo", "f*"), "simple glob fail");
ok(pagespec_match("foo", "page(foo)"), "page()");
print pagespec_match("foo", "page(foo)")."\n";
ok(! pagespec_match("foo", "page(bar)"), "page() fail");
ok(! pagespec_match("foo.png", "page(foo.png)"), "page() fails on non-page");
ok(! pagespec_match("foo.png", "page(foo*)"), "page() fails on non-page glob");
ok(pagespec_match("foo", "page(foo)"), "page() glob");
ok(pagespec_match("foo", "page(f*)"), "page() glob fail");
ok(pagespec_match("foo", "link(bar)"), "link");
ok(pagespec_match("foo", "link(.)", location => "bar"), "link with .");
ok(! pagespec_match("foo", "link(.)"), "link with . but missing location");
ok(pagespec_match("foo", "link(ba?)"), "glob link");
ok(! pagespec_match("foo", "link(quux)"), "failed link");
ok(! pagespec_match("foo", "link(qu*)"), "failed glob link");
ok(pagespec_match("bugs/foo", "link(done)", location => "bugs/done"), "link match to bestlink");
ok(! pagespec_match("examples/softwaresite/bugs/done", "link(done)", 
		location => "bugs/done"), "link match to bestlink");
ok(pagespec_match("examples/softwaresite/bugs/fails_to_frobnicate", 
		"link(./done)", location => "examples/softwaresite/bugs/done"), "link relative");
ok(! pagespec_match("foo", "link(./bar)", location => "foo/bar"), "link relative fail");
ok(pagespec_match("bar", "backlink(foo)"), "backlink");
ok(! pagespec_match("quux", "backlink(foo)"), "failed backlink");
ok(! pagespec_match("bar", ""), "empty pagespec should match nothing");
ok(! pagespec_match("bar", "    	"), "blank pagespec should match nothing");
ok(pagespec_match("ook", "link(blog/tags/foo)"), "link internal absolute success");
ok(pagespec_match("ook", "link(/blog/tags/foo)"), "link explicit absolute success");
ok(pagespec_match("meh", "!link(done)"), "negated failing match is a success");

$ENV{TZ}="GMT";
$IkiWiki::pagectime{foo}=1154532692; # Wed Aug  2 11:26 EDT 2006
$IkiWiki::pagectime{bar}=1154532695; # after
ok(pagespec_match("foo", "created_before(bar)"));
ok(! pagespec_match("foo", "created_after(bar)"));
ok(! pagespec_match("bar", "created_before(foo)"));
ok(pagespec_match("bar", "created_after(foo)"));
ok(pagespec_match("foo", "creation_year(2006)"), "year");
ok(! pagespec_match("foo", "creation_year(2005)"), "other year");
ok(pagespec_match("foo", "creation_month(8)"), "month");
ok(! pagespec_match("foo", "creation_month(9)"), "other month");
ok(pagespec_match("foo", "creation_day(2)"), "day");
ok(! pagespec_match("foo", "creation_day(3)"), "other day");

ok(! pagespec_match("foo", "no_such_function(foo)"), "foo");

my $ret=pagespec_match("foo", "(invalid");
ok(! $ret, "syntax error");
ok($ret =~ /syntax error/, "error message");

$ret=pagespec_match("foo", "bar or foo");
ok($ret, "simple match");
is($ret, "foo matches foo", "stringified return");

my $i=pagespec_match("foo", "link(bar)")->influences;
is(join(",", keys %$i), 'foo', "link is influenced by the page with the link");
$i=pagespec_match("bar", "backlink(foo)")->influences;
is(join(",", keys %$i), 'foo', "backlink is influenced by the page with the link");
$i=pagespec_match("bar", "backlink(foo)")->influences;
is(join(",", keys %$i), 'foo', "backlink is influenced by the page with the link");
$i=pagespec_match("bar", "created_before(foo)")->influences;
is(join(",", keys %$i), 'foo', "created_before is influenced by the comparison page");
$i=pagespec_match("bar", "created_after(foo)")->influences;
is(join(",", keys %$i), 'foo', "created_after is influenced by the comparison page");
$i=pagespec_match("foo", "link(baz) and created_after(bar)")->influences;
is(join(",", sort keys %$i), 'bar,foo', "influences add up over AND");
$i=pagespec_match("foo", "link(baz) and created_after(bar)")->influences;
is(join(",", sort keys %$i), 'bar,foo', "influences add up over OR");
$i=pagespec_match("foo", "!link(baz) and !created_after(bar)")->influences;
is(join(",", sort keys %$i), 'bar,foo', "influences unaffected by negation");
$i=pagespec_match("foo", "!link(baz) and !created_after(bar)")->influences;
is(join(",", sort keys %$i), 'bar,foo', "influences unaffected by negation");
$i=pagespec_match("meh", "!link(done)")->influences;
is(join(",", sort keys %$i), 'meh', "a negated, failing link test is successful, so the page is a link influence");
