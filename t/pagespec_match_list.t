#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 126;

BEGIN { use_ok("IkiWiki"); }

%config=IkiWiki::defaultconfig();
$config{srcdir}=$config{destdir}="/dev/null";
IkiWiki::checkconfig();

{
	package IkiWiki::SortSpec;

	sub cmp_raw_path { $a cmp $b }
}

%pagesources=(
	foo => "foo.mdwn",
	foo2 => "foo2.mdwn",
	foo3 => "foo3.mdwn",
	bar => "bar.mdwn",
	"post/1" => "post/1.mdwn",
	"post/2" => "post/2.mdwn",
	"post/3" => "post/3.mdwn",
);
$IkiWiki::pagectime{foo} = 2;
$IkiWiki::pagectime{foo2} = 2;
$IkiWiki::pagectime{foo3} = 1;
$IkiWiki::pagectime{foo4} = 1;
$IkiWiki::pagectime{foo5} = 1;
$IkiWiki::pagectime{bar} = 3;
$IkiWiki::pagectime{"post/1"} = 6;
$IkiWiki::pagectime{"post/2"} = 6;
$IkiWiki::pagectime{"post/3"} = 6;
$links{foo}=[qw{post/1 post/2}];
$links{foo2}=[qw{bar}];
$links{foo3}=[qw{bar}];

is_deeply([pagespec_match_list("foo", "bar")], ["bar"]);
is_deeply([sort(pagespec_match_list("foo", "* and !post/*"))], ["bar", "foo", "foo2", "foo3"]);
is_deeply([sort(pagespec_match_list("foo", "post/*"))], ["post/1", "post/2", "post/3"]);
is_deeply([pagespec_match_list("foo", "post/*", sort => "title")],
	["post/1", "post/2", "post/3"]);
is_deeply([pagespec_match_list("foo", "post/*", sort => "title", reverse => 1)],
	["post/3", "post/2", "post/1"]);
is_deeply([pagespec_match_list("foo", "post/*", sort => "title", num => 2)],
	["post/1", "post/2"]);
is_deeply([pagespec_match_list("foo", "post/*", sort => "title", num => 50)],
	["post/1", "post/2", "post/3"]);
is_deeply([pagespec_match_list("foo", "post/*", sort => "title", num => 50, reverse => 1)],
	["post/3", "post/2", "post/1"]);
is_deeply([pagespec_match_list("foo", "post/*", sort => "title",
                         filter => sub { $_[0] =~ /3/}) ],
	["post/1", "post/2"]);
is_deeply([pagespec_match_list("foo", "*", sort => "raw_path", num => 2)],
	["bar", "foo"]);
is_deeply([pagespec_match_list("foo", "foo* or bar*",
		sort => "-age title")], # oldest first, break ties by title
	["foo3", "foo", "foo2", "bar"]);
my $r=eval { pagespec_match_list("foo", "beep") };
ok(eval { pagespec_match_list("foo", "beep") } == 0);
ok(! $@, "does not fail with error when unable to match anything");
eval { pagespec_match_list("foo", "this is not a legal pagespec!") };
ok($@, "fails with error when pagespec bad");

# A pagespec that requires page metadata should add influences
# as an explicit dependency. In the case of a link, a links dependency.
foreach my $spec ("* and link(bar)", "* or link(bar)") {
	pagespec_match_list("foo2", $spec, deptype => deptype("presence"));
	ok($IkiWiki::depends{foo2}{$spec} & $IkiWiki::DEPEND_PRESENCE);
	ok(! ($IkiWiki::depends{foo2}{$spec} & ($IkiWiki::DEPEND_CONTENT | $IkiWiki::DEPEND_LINKS)));
	ok($IkiWiki::depends_simple{foo2}{foo2} == $IkiWiki::DEPEND_LINKS);
	%IkiWiki::depends_simple=();
	%IkiWiki::depends=();
	pagespec_match_list("foo3", $spec, deptype => deptype("links"));
	ok($IkiWiki::depends{foo3}{$spec} & $IkiWiki::DEPEND_LINKS);
	ok(! ($IkiWiki::depends{foo3}{$spec} & ($IkiWiki::DEPEND_CONTENT | $IkiWiki::DEPEND_PRESENCE)));
	ok($IkiWiki::depends_simple{foo3}{foo3} == $IkiWiki::DEPEND_LINKS);
	%IkiWiki::depends_simple=();
	%IkiWiki::depends=();
}

# A link pagespec is influenced by the pages that currently contain the link.
# It is not influced by pages that do not currently contain the link,
# because if those pages were changed to contain it, regular dependency
# handling would be triggered.
foreach my $spec ("* and link(bar)", "link(bar)", "no_such_page or link(bar)") {
	pagespec_match_list("foo2", $spec);
	ok($IkiWiki::depends_simple{foo2}{foo2} == $IkiWiki::DEPEND_LINKS);
	ok(! exists $IkiWiki::depends_simple{foo2}{foo}, $spec);
	%IkiWiki::depends_simple=();
	%IkiWiki::depends=();
}

# Oppositely, a pagespec that tests for pages that do not have a link
# is not influenced by pages that currently contain the link, but
# is instead influenced by pages that currently do not (but that
# could be changed to have it).
foreach my $spec ("* and !link(bar)", "* and !(!(!link(bar)))") {
	pagespec_match_list("foo2", $spec);
	ok(! exists $IkiWiki::depends_simple{foo2}{foo2});
	ok($IkiWiki::depends_simple{foo2}{foo} == $IkiWiki::DEPEND_LINKS, $spec);
	%IkiWiki::depends_simple=();
	%IkiWiki::depends=();
}

# a pagespec with backlinks() will add as an influence the page with the links
foreach my $spec ("bar or (backlink(foo) and !*.png)", "backlink(foo)", "!backlink(foo)") {
	pagespec_match_list("foo2", $spec, deptype => deptype("presence"));
	ok($IkiWiki::depends{foo2}{$spec} & $IkiWiki::DEPEND_PRESENCE);
	ok(! ($IkiWiki::depends{foo2}{$spec} & ($IkiWiki::DEPEND_CONTENT | $IkiWiki::DEPEND_LINKS)));
	ok($IkiWiki::depends_simple{foo2}{foo} == $IkiWiki::DEPEND_LINKS);
	ok(! exists $IkiWiki::depends_simple{foo2}{foo2});
	%IkiWiki::depends_simple=();
	%IkiWiki::depends=();
	pagespec_match_list("foo2", $spec, deptype => deptype("links"));
	ok($IkiWiki::depends{foo2}{$spec} & $IkiWiki::DEPEND_LINKS);
	ok(! ($IkiWiki::depends{foo2}{$spec} & ($IkiWiki::DEPEND_PRESENCE | $IkiWiki::DEPEND_CONTENT)));
	ok($IkiWiki::depends_simple{foo2}{foo} == $IkiWiki::DEPEND_LINKS);
	ok(! exists $IkiWiki::depends_simple{foo2}{foo2});
	%IkiWiki::depends_simple=();
	%IkiWiki::depends=();
	pagespec_match_list("foo2", $spec, deptype => deptype("presence", "links"));
	ok($IkiWiki::depends{foo2}{$spec} & $IkiWiki::DEPEND_PRESENCE);
	ok($IkiWiki::depends{foo2}{$spec} & $IkiWiki::DEPEND_LINKS);
	ok(! ($IkiWiki::depends{foo2}{$spec} & $IkiWiki::DEPEND_CONTENT));
	ok($IkiWiki::depends_simple{foo2}{foo} == $IkiWiki::DEPEND_LINKS);
	ok(! exists $IkiWiki::depends_simple{foo2}{foo2});
	%IkiWiki::depends_simple=();
	%IkiWiki::depends=();
	pagespec_match_list("foo2", $spec);
	ok($IkiWiki::depends{foo2}{$spec} & $IkiWiki::DEPEND_CONTENT);
	ok(! ($IkiWiki::depends{foo2}{$spec} & ($IkiWiki::DEPEND_PRESENCE | $IkiWiki::DEPEND_LINKS)));
	ok($IkiWiki::depends_simple{foo2}{foo} == $IkiWiki::DEPEND_LINKS);
	%IkiWiki::depends_simple=();
	%IkiWiki::depends=();
}

# Hard fails due to a glob, etc, will block influences of other anded terms.
foreach my $spec ("nosuchpage and link(bar)", "link(bar) and nosuchpage",
                  "link(bar) and */Discussion", "*/Discussion and link(bar)",
                  "!foo2 and link(bar)", "link(bar) and !foo2") {
	pagespec_match_list("foo2", $spec, deptype => deptype("presence"));
	ok($IkiWiki::depends{foo2}{$spec} & $IkiWiki::DEPEND_PRESENCE);
	ok(! ($IkiWiki::depends{foo2}{$spec} & ($IkiWiki::DEPEND_CONTENT | $IkiWiki::DEPEND_LINKS)));
	ok(! exists $IkiWiki::depends_simple{foo2}{foo2}, "no influence from $spec");
	%IkiWiki::depends_simple=();
	%IkiWiki::depends=();
}

# A hard fail will not block influences of other ored terms.
foreach my $spec ("nosuchpage or link(bar)", "link(bar) or nosuchpage",
                  "link(bar) or */Discussion", "*/Discussion or link(bar)",
                  "!foo2 or link(bar)", "link(bar) or !foo2",
                  "link(bar) or (!foo2 and !foo1)") {
	pagespec_match_list("foo2", $spec, deptype => deptype("presence"));
	ok($IkiWiki::depends{foo2}{$spec} & $IkiWiki::DEPEND_PRESENCE);
	ok(! ($IkiWiki::depends{foo2}{$spec} & ($IkiWiki::DEPEND_CONTENT | $IkiWiki::DEPEND_LINKS)));
	ok($IkiWiki::depends_simple{foo2}{foo2} == $IkiWiki::DEPEND_LINKS);
	%IkiWiki::depends_simple=();
	%IkiWiki::depends=();
}

my @ps;
foreach my $p (100..500) {
	$IkiWiki::pagectime{"p/$p"} = $p;
	$pagesources{"p/$p"} = "p/$p.mdwn";
	unshift @ps, "p/$p";
}
is_deeply([pagespec_match_list("foo", "p/*", sort => "age")],
	[@ps]);
is_deeply([pagespec_match_list("foo", "p/*", sort => "age", num => 20)],
	[@ps[0..19]]);
