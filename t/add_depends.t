#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 88;

BEGIN { use_ok("IkiWiki"); }
%config=IkiWiki::defaultconfig();
$config{srcdir}=$config{destdir}="/dev/null";
IkiWiki::checkconfig();

$pagesources{"foo$_"}="foo$_.mdwn" for 0..9;

# avoids adding an unparseable pagespec
ok(! add_depends("foo0", "foo and (bar"));
ok(! add_depends("foo0", "foo another"));

# simple and not-so-simple dependencies split
ok(add_depends("foo0", "*"));
ok(add_depends("foo0", "bar"));
ok(add_depends("foo0", "BAZ"));
ok(exists $IkiWiki::depends_simple{foo0}{"bar"});
ok(exists $IkiWiki::depends_simple{foo0}{"baz"}); # lowercase
ok(! exists $IkiWiki::depends_simple{foo0}{"*"});
ok(! exists $IkiWiki::depends{foo0}{"bar"});
ok(! exists $IkiWiki::depends{foo0}{"baz"});

# default dependencies are content dependencies
ok($IkiWiki::depends{foo0}{"*"} & $IkiWiki::DEPEND_CONTENT);
ok(! ($IkiWiki::depends{foo0}{"*"} & ($IkiWiki::DEPEND_PRESENCE | $IkiWiki::DEPEND_LINKS)));
ok($IkiWiki::depends_simple{foo0}{"bar"} & $IkiWiki::DEPEND_CONTENT);
ok(! ($IkiWiki::depends_simple{foo0}{"bar"} & ($IkiWiki::DEPEND_PRESENCE | $IkiWiki::DEPEND_LINKS)));

# adding other dep types standalone
ok(add_depends("foo2", "*", presence => 1));
ok(add_depends("foo2", "bar", links => 1));
ok($IkiWiki::depends{foo2}{"*"} & $IkiWiki::DEPEND_PRESENCE);
ok(! ($IkiWiki::depends{foo2}{"*"} & ($IkiWiki::DEPEND_CONTENT | $IkiWiki::DEPEND_LINKS)));
ok($IkiWiki::depends_simple{foo2}{"bar"} & $IkiWiki::DEPEND_LINKS);
ok(! ($IkiWiki::depends_simple{foo2}{"bar"} & ($IkiWiki::DEPEND_PRESENCE | $IkiWiki::DEPEND_CONTENT)));

# adding combined dep types
ok(add_depends("foo2", "baz", links => 1, presence => 1));
ok($IkiWiki::depends_simple{foo2}{"baz"} & $IkiWiki::DEPEND_LINKS);
ok($IkiWiki::depends_simple{foo2}{"baz"} & $IkiWiki::DEPEND_PRESENCE);
ok(! ($IkiWiki::depends_simple{foo2}{"baz"} & $IkiWiki::DEPEND_CONTENT));

# adding dep types to existing dependencies should merge the flags
ok(add_depends("foo2", "baz"));
ok($IkiWiki::depends_simple{foo2}{"baz"} & $IkiWiki::DEPEND_LINKS);
ok($IkiWiki::depends_simple{foo2}{"baz"} & $IkiWiki::DEPEND_PRESENCE);
ok(($IkiWiki::depends_simple{foo2}{"baz"} & $IkiWiki::DEPEND_CONTENT));
ok(add_depends("foo2", "bar", presence => 1)); # had only links before
ok($IkiWiki::depends_simple{foo2}{"bar"} & ($IkiWiki::DEPEND_LINKS | $IkiWiki::DEPEND_PRESENCE));
ok(! ($IkiWiki::depends_simple{foo2}{"bar"} & $IkiWiki::DEPEND_CONTENT));
ok(add_depends("foo0", "bar", links => 1)); # had only content before
ok($IkiWiki::depends{foo0}{"*"} & ($IkiWiki::DEPEND_CONTENT | $IkiWiki::DEPEND_LINKS));
ok(! ($IkiWiki::depends{foo0}{"*"} & $IkiWiki::DEPEND_PRESENCE));

# Adding a pagespec that requires page metadata should add the influence
# as an explicit content dependency.
$links{foo0}=$links{foo9}=[qw{bar baz}];
foreach my $spec ("* and ! link(bar)", "* or link(bar)") {
	ok(add_depends("foo3", $spec, presence => 1));
	ok($IkiWiki::depends{foo3}{$spec} & $IkiWiki::DEPEND_PRESENCE);
	ok(! ($IkiWiki::depends{foo3}{$spec} & ($IkiWiki::DEPEND_CONTENT | $IkiWiki::DEPEND_LINKS)));
	ok($IkiWiki::depends_simple{foo3}{foo3} == $IkiWiki::DEPEND_CONTENT);
	ok(add_depends("foo4", $spec, links => 1));
	ok($IkiWiki::depends{foo4}{$spec} & $IkiWiki::DEPEND_LINKS);
	ok(! ($IkiWiki::depends{foo4}{$spec} & ($IkiWiki::DEPEND_CONTENT | $IkiWiki::DEPEND_PRESENCE)));
	ok($IkiWiki::depends_simple{foo4}{foo4} == $IkiWiki::DEPEND_CONTENT);
}

# a pagespec with backlinks() will add as an influence the page with the links
$links{foo0}=[qw{foo5 foo7}];
foreach my $spec ("bugs or (backlink(foo0) and !*.png)", "backlink(foo)") {
	ok(add_depends("foo5", $spec, presence => 1));
	ok($IkiWiki::depends{foo5}{$spec} & $IkiWiki::DEPEND_PRESENCE);
	ok(! ($IkiWiki::depends{foo5}{$spec} & ($IkiWiki::DEPEND_CONTENT | $IkiWiki::DEPEND_LINKS)));
	ok($IkiWiki::depends_simple{foo5}{foo0} == $IkiWiki::DEPEND_CONTENT);
	ok(add_depends("foo6", $spec, links => 1));
	ok($IkiWiki::depends{foo6}{$spec} & $IkiWiki::DEPEND_LINKS);
	ok(! ($IkiWiki::depends{foo6}{$spec} & ($IkiWiki::DEPEND_PRESENCE | $IkiWiki::DEPEND_CONTENT)));
	ok($IkiWiki::depends_simple{foo5}{foo0} == $IkiWiki::DEPEND_CONTENT);
	ok(add_depends("foo7", $spec, presence => 1, links => 1));
	ok($IkiWiki::depends{foo7}{$spec} & $IkiWiki::DEPEND_PRESENCE);
	ok($IkiWiki::depends{foo7}{$spec} & $IkiWiki::DEPEND_LINKS);
	ok(! ($IkiWiki::depends{foo7}{$spec} & $IkiWiki::DEPEND_CONTENT));
	ok($IkiWiki::depends_simple{foo7}{foo0} == $IkiWiki::DEPEND_CONTENT);
	ok(add_depends("foo8", $spec));
	ok($IkiWiki::depends{foo8}{$spec} & $IkiWiki::DEPEND_CONTENT);
	ok(! ($IkiWiki::depends{foo8}{$spec} & ($IkiWiki::DEPEND_PRESENCE | $IkiWiki::DEPEND_LINKS)));
	ok($IkiWiki::depends_simple{foo8}{foo0} == $IkiWiki::DEPEND_CONTENT);
}

# content is the default if unknown types are entered
ok(add_depends("foo9", "*", presenCe => 1));
ok($IkiWiki::depends{foo9}{"*"} & $IkiWiki::DEPEND_CONTENT);
ok(! ($IkiWiki::depends{foo9}{"*"} & ($IkiWiki::DEPEND_PRESENCE | $IkiWiki::DEPEND_LINKS)));
