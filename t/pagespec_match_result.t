#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 138;

BEGIN { use_ok("IkiWiki"); }

# Note that new objects have to be constructed freshly for each test, since
# object states are mutated as they are combined.
sub S { IkiWiki::SuccessReason->new("match", @_) }
sub F { IkiWiki::FailReason->new("no match", @_) }
sub E { IkiWiki::ErrorReason->new("error in matching", @_) }

ok(S() eq "match");
ok(F() eq "no match");
ok(E() eq "error in matching");

ok(S());
ok(! F());
ok(! E());

ok(!(! S()));
ok(!(!(! F)));
ok(!(!(! E)));

ok(S() | F());
ok(F() | S());
ok(!(F() | E()));
ok(!(!S() | F() | E()));

ok(S() & S() & S());
ok(!(S() & E()));
ok(!(S() & F()));
ok(!(S() & F() & E()));
ok(S() & (F() | F() | S()));

# influence merging tests
foreach my $test (
		['$s | $f' => 1],	# OR merges
                ['! $s | ! $f' => 1],	# OR merges with negated terms too
		['!(!(!$s)) | $f' => 1],# OR merges with multiple negation too
		['$s | $f | E()' => 1],	# OR merges, even though E() has no influences
		['$s | E() | $f' => 1],	# ditto
		['E() | $s | $f' => 1],	# ditto
		['!$s | !$f | E()' => 1],# negated terms also do not block merges
		['!$s | E() | $f' => 1],# ditto
		['E() | $s | !$f' => 1],# ditto
		['$s & $f' => 1],	# AND merges if both items have influences
		['!$s & $f' => 1],	# AND merges negated terms too
		['$s & !$f' => 1],	# AND merges negated terms too
		['$s & $f & E()' => 0],	# AND fails to merge since E() has no influences
		['$s & E() & $f' => 0],	# ditto
		['E() & $s & $f' => 0],	# ditto
		) {
	my $op=$test->[0];
	my $influence=$test->[1];

	my $s=S(foo => 1, bar => 1);
	is($s->influences->{foo}, 1);
	is($s->influences->{bar}, 1);
	my $f=F(bar => 2, baz => 1);
	is($f->influences->{bar}, 2);
	is($f->influences->{baz}, 1);
	my $c = eval $op;
	ok(ref $c);
	if ($influence) {
		is($c->influences->{foo}, 1, "foo ($op)");
		is($c->influences->{bar}, (1 | 2), "bar ($op)");
		is($c->influences->{baz}, 1, "baz ($op)");
	}
	else {
		ok(! %{$c->influences}, "no influence for ($op)");
	}
}

my $s=S(foo => 0, bar => 1);
$s->influences(baz => 1);
ok(! $s->influences->{foo}, "removed 0 influence");
ok(! $s->influences->{bar}, "removed 1 influence");
ok($s->influences->{baz}, "set influence");
ok($s->influences_static);
$s=S(foo => 0, bar => 1);
$s->influences(baz => 1, "" => 1);
ok(! $s->influences_static);
