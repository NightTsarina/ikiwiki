#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 67;

BEGIN { use_ok("IkiWiki"); }

# Note that new objects have to be constructed freshly for each test, since
# object states are mutated as they are combined.
sub S { IkiWiki::SuccessReason->new("match") }
sub F { IkiWiki::FailReason->new("no match") }
sub E { IkiWiki::ErrorReason->new("error in matching") }

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

# influences are always merged, no matter the operation performed,
# as long as the two items are always both present
foreach my $op ('$s | $f', '$s & $f', '$s & $f & E()', '$s | E() | $f',
                '! $s | ! $f', '!(!(!$s)) | $f') {
	my $s=S();
	$s->influences(foo => 1, bar => 1);
	is($s->influences->{foo}, 1);
	is($s->influences->{bar}, 1);
	my $f=F();
	$f->influences(bar => 2, baz => 1);
	is($f->influences->{bar}, 2);
	is($f->influences->{baz}, 1);
	my $c = eval $op;
	ok(ref $c);
	is($c->influences->{foo}, 1, "foo ($op)");
	is($c->influences->{bar}, (1 | 2), "bar ($op)");
	is($c->influences->{baz}, 1, "baz ($op)");
}
