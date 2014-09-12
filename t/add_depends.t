#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 40;

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
ok(add_depends("foo2", "*", deptype("presence")));
ok(add_depends("foo2", "bar", deptype("links")));
ok($IkiWiki::depends{foo2}{"*"} & $IkiWiki::DEPEND_PRESENCE);
ok(! ($IkiWiki::depends{foo2}{"*"} & ($IkiWiki::DEPEND_CONTENT | $IkiWiki::DEPEND_LINKS)));
ok($IkiWiki::depends_simple{foo2}{"bar"} & $IkiWiki::DEPEND_LINKS);
ok(! ($IkiWiki::depends_simple{foo2}{"bar"} & ($IkiWiki::DEPEND_PRESENCE | $IkiWiki::DEPEND_CONTENT)));

# adding combined dep types
ok(add_depends("foo2", "baz", deptype("links", "presence")));
ok($IkiWiki::depends_simple{foo2}{"baz"} & $IkiWiki::DEPEND_LINKS);
ok($IkiWiki::depends_simple{foo2}{"baz"} & $IkiWiki::DEPEND_PRESENCE);
ok(! ($IkiWiki::depends_simple{foo2}{"baz"} & $IkiWiki::DEPEND_CONTENT));

# adding dep types to existing dependencies should merge the flags
ok(add_depends("foo2", "baz"));
ok($IkiWiki::depends_simple{foo2}{"baz"} & $IkiWiki::DEPEND_LINKS);
ok($IkiWiki::depends_simple{foo2}{"baz"} & $IkiWiki::DEPEND_PRESENCE);
ok(($IkiWiki::depends_simple{foo2}{"baz"} & $IkiWiki::DEPEND_CONTENT));
ok(add_depends("foo2", "bar", deptype("presence"))); # had only links before
ok($IkiWiki::depends_simple{foo2}{"bar"} & ($IkiWiki::DEPEND_LINKS | $IkiWiki::DEPEND_PRESENCE));
ok(! ($IkiWiki::depends_simple{foo2}{"bar"} & $IkiWiki::DEPEND_CONTENT));
ok(add_depends("foo0", "bar", deptype("links"))); # had only content before
ok($IkiWiki::depends{foo0}{"*"} & ($IkiWiki::DEPEND_CONTENT | $IkiWiki::DEPEND_LINKS));
ok(! ($IkiWiki::depends{foo0}{"*"} & $IkiWiki::DEPEND_PRESENCE));

# content is the default if unknown types are entered
ok(add_depends("foo9", "*", deptype("monkey")));
ok($IkiWiki::depends{foo9}{"*"} & $IkiWiki::DEPEND_CONTENT);
ok(! ($IkiWiki::depends{foo9}{"*"} & ($IkiWiki::DEPEND_PRESENCE | $IkiWiki::DEPEND_LINKS)));

# Influences are added for dependencies involving links.
$pagesources{"foo"}="foo.mdwn";
$links{foo}=[qw{bar}]; 
$pagesources{"bar"}="bar.mdwn";
$links{bar}=[qw{}];
ok(add_depends("foo", "link(bar) and backlink(meep)"));
ok($IkiWiki::depends_simple{foo}{foo} == $IkiWiki::DEPEND_LINKS);
