#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 34;

BEGIN { use_ok("IkiWiki"); }

$IkiWiki::hooks{preprocess}{foo}{call}=sub {
	my @bits;
	while (@_) {
		my $key=shift;
		my $value=shift;
		next if $key eq 'page' || $key eq 'destpage' || $key eq 'preview';
		if (length $value) {
			push @bits, "$key => $value";
		}
		else {
			push @bits, $key;
		}
	}
	return "foo(".join(", ", @bits).")";
};

is(IkiWiki::preprocess("foo", "foo", "[[foo]]", 0, 0), "[[foo]]", "not wikilink");
is(IkiWiki::preprocess("foo", "foo", "[[foo ]]", 0, 0), "foo()", "simple");
is(IkiWiki::preprocess("foo", "foo", "[[!foo ]]", 0, 0), "foo()", "prefixed");
is(IkiWiki::preprocess("foo", "foo", "[[!foo]]", 0, 0), "[[!foo]]", "prefixed, no space");
is(IkiWiki::preprocess("foo", "foo", "[[foo a=1]]", 0, 0), "foo(a => 1)");
is(IkiWiki::preprocess("foo", "foo", q{[[foo a="1"]]}, 0, 0), "foo(a => 1)");
is(IkiWiki::preprocess("foo", "foo", q{[[foo a="""1"""]]}, 0, 0), "foo(a => 1)");
is(IkiWiki::preprocess("foo", "foo", q{[[foo a=""]]}, 0, 0), "foo(a)");
is(IkiWiki::preprocess("foo", "foo", q{[[foo a="" b="1"]]}, 0, 0), "foo(a, b => 1)");
is(IkiWiki::preprocess("foo", "foo", q{[[foo a=""""""]]}, 0, 0), "foo(a)");
is(IkiWiki::preprocess("foo", "foo", q{[[foo a="""""" b="1"]]}, 0, 0), "foo(a, b => 1)");
is(IkiWiki::preprocess("foo", "foo", q{[[foo a="""""" b="""1"""]]}, 0, 0), "foo(a, b => 1)");
is(IkiWiki::preprocess("foo", "foo", q{[[foo a="""""" b=""""""]]}, 0, 0), "foo(a, b)");
is(IkiWiki::preprocess("foo", "foo", q{[[foo a="" b=""""""]]}, 0, 0), "foo(a, b)");
is(IkiWiki::preprocess("foo", "foo", q{[[foo a="" b="""1"""]]}, 0, 0), "foo(a, b => 1)");
is(IkiWiki::preprocess("foo", "foo", "[[foo a=\"1 2 3 4\"]]", 0, 0), "foo(a => 1 2 3 4)");
is(IkiWiki::preprocess("foo", "foo", "[[foo ]] then [[foo a=2]]", 0, 0),
	"foo() then foo(a => 2)");
is(IkiWiki::preprocess("foo", "foo", "[[foo b c \"d and e=f\"]]", 0, 0), "foo(b, c, d and e=f)");
is(IkiWiki::preprocess("foo", "foo", "[[foo a=1 b c=1]]", 0, 0),
	"foo(a => 1, b, c => 1)");
is(IkiWiki::preprocess("foo", "foo", "[[foo    a=1 b   c=1    \t\t]]", 0, 0),
	"foo(a => 1, b, c => 1)", "whitespace");
is(IkiWiki::preprocess("foo", "foo", "[[foo a=1\nb \nc=1]]", 0, 0),
	"foo(a => 1, b, c => 1)", "multiline directive");
is(IkiWiki::preprocess("foo", "foo", "[[foo a=1 a=2 a=3]]", 0, 0),
	"foo(a => 1, a => 2, a => 3)", "dup item");
is(IkiWiki::preprocess("foo", "foo", '[[foo a="[[bracketed]]" b=1]]', 0, 0),
	"foo(a => [[bracketed]], b => 1)");
my $multiline="here is my \"first\"
!! [[multiline ]] !!
string!";
is(IkiWiki::preprocess("foo", "foo", '[[foo a="""'.$multiline.'"""]]', 0, 0),
	"foo(a => $multiline)");
is(IkiWiki::preprocess("foo", "foo", '[[foo """'.$multiline.'"""]]', 0, 0),
	"foo($multiline)");
is(IkiWiki::preprocess("foo", "foo", '[[foo a="""'.$multiline.'""" b="foo"]]', 0, 0),
	"foo(a => $multiline, b => foo)");
is(IkiWiki::preprocess("foo", "foo", '[[foo a="""'."\n".$multiline."\n".'""" b="foo"]]', 0, 0),
	"foo(a => $multiline, b => foo)", "leading/trailing newline stripped");
my $long='[[foo a="""'.("a" x 100000).'';
is(IkiWiki::preprocess("foo", "foo", $long, 0, 0), $long,
	"unterminated triple-quoted string inside unterminated directive(should not warn about over-recursion)");
is(IkiWiki::preprocess("foo", "foo", $long."]]", 0, 0), $long."]]",
	"unterminated triple-quoted string is not treated as a bare word");

is(IkiWiki::preprocess("foo", "foo", "[[!foo a=<<HEREDOC\n".$multiline."\nHEREDOC]]", 0, 0),
	"foo(a => $multiline)", "nested strings via heredoc (for key)");
is(IkiWiki::preprocess("foo", "foo", "[[!foo <<HEREDOC\n".$multiline."\nHEREDOC]]", 0, 0),
	"foo($multiline)", "nested strings via heredoc (without keyless)");
is(IkiWiki::preprocess("foo", "foo", "[[!foo '''".$multiline."''']]", 0, 0),
	"foo($multiline)", "triple-single-quoted multiline string");

TODO: {
	local $TODO = "nested strings not yet implemented";

	$multiline='here is a string containing another [[foo val="""string""]]';
	is(IkiWiki::preprocess("foo", "foo", '[[foo a="""'.$multiline.'"""]]', 0, 0),
		"foo(a => $multiline)", "nested multiline strings");
}
