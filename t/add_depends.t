#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 50;

BEGIN { use_ok("IkiWiki"); }
%config=IkiWiki::defaultconfig();
$config{srcdir}=$config{destdir}="/dev/null";
IkiWiki::checkconfig();

# avoids adding an unparseable pagespec
ok(! add_depends("foo", "foo and (bar"));
ok(! add_depends("foo", "foo another"));

# simple and not-so-simple dependencies split
ok(add_depends("foo", "*"));
ok(add_depends("foo", "bar"));
ok(add_depends("foo", "BAZ"));
ok(exists $IkiWiki::depends_simple{foo}{"bar"});
ok(exists $IkiWiki::depends_simple{foo}{"baz"}); # lowercase
ok(! exists $IkiWiki::depends_simple{foo}{"*"});
ok(! exists $IkiWiki::depends{foo}{"bar"});
ok(! exists $IkiWiki::depends{foo}{"baz"});

# default dependencies are content dependencies
ok($IkiWiki::depends{foo}{"*"} & $IkiWiki::DEPEND_CONTENT);
ok(! ($IkiWiki::depends{foo}{"*"} & ($IkiWiki::DEPEND_PRESENCE | $IkiWiki::DEPEND_LINKS)));
ok($IkiWiki::depends_simple{foo}{"bar"} & $IkiWiki::DEPEND_CONTENT);
ok(! ($IkiWiki::depends_simple{foo}{"bar"} & ($IkiWiki::DEPEND_PRESENCE | $IkiWiki::DEPEND_LINKS)));

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

# adding a pagespec that requires page metadata should cause a fallback to
# a content dependency
foreach my $spec ("* and ! link(bar)", "* or link(bar)", "unknownspec()",
	"title(hi)",
	"* or backlink(yo)", # this one could actually be acceptably be
	                     # detected to not need a content dep .. in
			     # theory!
	) {
	ok(add_depends("foo3", $spec, presence => 1));
	ok($IkiWiki::depends{foo3}{$spec} & $IkiWiki::DEPEND_CONTENT);
	ok(! ($IkiWiki::depends{foo3}{$spec} & ($IkiWiki::DEPEND_PRESENCE | $IkiWiki::DEPEND_LINKS)));
}

# adding dep types to existing dependencies should merge the flags
ok(add_depends("foo2", "baz"));
ok($IkiWiki::depends_simple{foo2}{"baz"} & $IkiWiki::DEPEND_LINKS);
ok($IkiWiki::depends_simple{foo2}{"baz"} & $IkiWiki::DEPEND_PRESENCE);
ok(($IkiWiki::depends_simple{foo2}{"baz"} & $IkiWiki::DEPEND_CONTENT));
ok(add_depends("foo2", "bar", presence => 1)); # had only links before
ok($IkiWiki::depends_simple{foo2}{"bar"} & ($IkiWiki::DEPEND_LINKS | $IkiWiki::DEPEND_PRESENCE));
ok(! ($IkiWiki::depends_simple{foo2}{"bar"} & $IkiWiki::DEPEND_CONTENT));
ok(add_depends("foo", "bar", links => 1)); # had only content before
ok($IkiWiki::depends{foo}{"*"} & ($IkiWiki::DEPEND_CONTENT | $IkiWiki::DEPEND_LINKS));
ok(! ($IkiWiki::depends{foo}{"*"} & $IkiWiki::DEPEND_PRESENCE));
