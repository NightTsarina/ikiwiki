#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 25;

BEGIN { use_ok("IkiWiki"); }

%config=IkiWiki::defaultconfig();
$config{srcdir}=$config{destdir}="/dev/null";
IkiWiki::checkconfig();

sub test {
	my ($before, $after) = @_;

	$IkiWiki::SortSpec::a = $before;
	$IkiWiki::SortSpec::b = $after;
	my $r = IkiWiki::SortSpec::cmp_path();

	if ($before eq $after) {
		is($r, 0);
	}
	else {
		is($r, -1);
	}

	$IkiWiki::SortSpec::a = $after;
	$IkiWiki::SortSpec::b = $before;
	$r = IkiWiki::SortSpec::cmp_path();

	if ($before eq $after) {
		is($r, 0);
	}
	else {
		is($r, 1);
	}

	is_deeply([IkiWiki::SortSpec::sort_pages(\&IkiWiki::SortSpec::cmp_path, $before, $after)],
		[$before, $after]);
	is_deeply([IkiWiki::SortSpec::sort_pages(\&IkiWiki::SortSpec::cmp_path, $after, $before)],
		[$before, $after]);
}

test("a/b/c", "a/b/c");
test("a/b", "a/c");
test("a/z", "z/a");
test("a", "a/b");
test("a", "a/b");
test("a/z", "ab");
