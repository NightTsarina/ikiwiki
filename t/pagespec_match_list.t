#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 88;

BEGIN { use_ok("IkiWiki"); }

%config=IkiWiki::defaultconfig();
$config{srcdir}=$config{destdir}="/dev/null";
IkiWiki::checkconfig();

%pagesources=(
	foo => "foo.mdwn",
	foo2 => "foo2.mdwn",
	foo3 => "foo3.mdwn",
	bar => "bar.mdwn",
	"post/1" => "post/1.mdwn",
	"post/2" => "post/2.mdwn",
	"post/3" => "post/3.mdwn",
);
$links{foo}=[qw{post/1 post/2}];
$links{foo2}=[qw{bar}];
$links{foo3}=[qw{bar}];

is_deeply([pagespec_match_list("foo", "bar")], ["bar"]);
is_deeply([sort(pagespec_match_list("foo", "* and !post/*"))], ["bar", "foo", "foo2", "foo3"]);
is_deeply([sort(pagespec_match_list("foo", "post/*"))], ["post/1", "post/2", "post/3"]);
is_deeply([pagespec_match_list("foo", "post/*", sort => "title", reverse => 1)],
	["post/3", "post/2", "post/1"]);
is_deeply([pagespec_match_list("foo", "post/*", sort => "title", num => 2)],
	["post/1", "post/2"]);
is_deeply([pagespec_match_list("foo", "post/*", sort => "title", num => 50)],
	["post/1", "post/2", "post/3"]);
is_deeply([pagespec_match_list("foo", "post/*", sort => "title",
                         filter => sub { $_[0] =~ /3/}) ],
	["post/1", "post/2"]);
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

# a pagespec with backlinks() will add as an influence the page with the links
foreach my $spec ("bar or (backlink(foo) and !*.png)", "backlink(foo)") {
	pagespec_match_list("foo2", $spec, deptype => deptype("presence"));
	ok($IkiWiki::depends{foo2}{$spec} & $IkiWiki::DEPEND_PRESENCE);
	ok(! ($IkiWiki::depends{foo2}{$spec} & ($IkiWiki::DEPEND_CONTENT | $IkiWiki::DEPEND_LINKS)));
	ok($IkiWiki::depends_simple{foo2}{foo} == $IkiWiki::DEPEND_LINKS);
	%IkiWiki::depends_simple=();
	%IkiWiki::depends=();
	pagespec_match_list("foo2", $spec, deptype => deptype("links"));
	ok($IkiWiki::depends{foo2}{$spec} & $IkiWiki::DEPEND_LINKS);
	ok(! ($IkiWiki::depends{foo2}{$spec} & ($IkiWiki::DEPEND_PRESENCE | $IkiWiki::DEPEND_CONTENT)));
	ok($IkiWiki::depends_simple{foo2}{foo} == $IkiWiki::DEPEND_LINKS);
	%IkiWiki::depends_simple=();
	%IkiWiki::depends=();
	pagespec_match_list("foo2", $spec, deptype => deptype("presence", "links"));
	ok($IkiWiki::depends{foo2}{$spec} & $IkiWiki::DEPEND_PRESENCE);
	ok($IkiWiki::depends{foo2}{$spec} & $IkiWiki::DEPEND_LINKS);
	ok(! ($IkiWiki::depends{foo2}{$spec} & $IkiWiki::DEPEND_CONTENT));
	ok($IkiWiki::depends_simple{foo2}{foo} == $IkiWiki::DEPEND_LINKS);
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
