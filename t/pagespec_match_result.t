#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 71;

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

# influences are always merged, no matter the operation performed,
# as long as the two items are always both present
foreach my $op ('$s | $f', '$s & $f', '$s & $f & E()', '$s | E() | $f',
                '! $s | ! $f', '!(!(!$s)) | $f') {
	my $s=S(foo => 1, bar => 1);
	is($s->influences->{foo}, 1);
	is($s->influences->{bar}, 1);
	my $f=F(bar => 2, baz => 1);
	is($f->influences->{bar}, 2);
	is($f->influences->{baz}, 1);
	my $c = eval $op;
	ok(ref $c);
	is($c->influences->{foo}, 1, "foo ($op)");
	is($c->influences->{bar}, (1 | 2), "bar ($op)");
	is($c->influences->{baz}, 1, "baz ($op)");
}

my $s=S(foo => 0, bar => 1);
$s->influences(baz => 1);
ok(! $s->influences->{foo}, "removed 0 influence");
ok(! $s->influences->{bar}, "removed 1 influence");
ok($s->influences->{baz}, "set influence");
ok($s->influences_static);

# influence blocking
my $r=F()->block & S(foo => 1);
ok(! $r->influences->{foo}, "failed blocker & influence -> does not pass");
$r=F()->block | S(foo => 1);
ok($r->influences->{foo}, "failed blocker | influence -> does pass");
$r=S(foo => 1) & F()->block;
ok(! $r->influences->{foo}, "influence & failed blocker -> does not pass");
$r=S(foo => 1) | F()->block;
ok($r->influences->{foo}, "influence | failed blocker -> does pass");
$r=S(foo => 1) & F()->block & S(foo => 2);
ok(! $r->influences->{foo}, "influence & failed blocker & influence -> does not pass");
$r=S(foo => 1) | F()->block | S(foo => 2);
ok($r->influences->{foo}, "influence | failed blocker | influence -> does pass");
$r=S()->block & S(foo => 1);
ok($r->influences->{foo}, "successful blocker -> does pass");
$r=(! S()->block) & S(foo => 1);
ok(! $r->influences->{foo}, "! successful blocker -> failed blocker");
