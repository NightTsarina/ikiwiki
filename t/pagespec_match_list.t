#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 10;

BEGIN { use_ok("IkiWiki"); }

%pagesources=(
	foo => "foo.mdwn",
	bar => "bar.mdwn",
	"post/1" => "post/1.mdwn",
	"post/2" => "post/2.mdwn",
	"post/3" => "post/3.mdwn",
);

is_deeply([pagespec_match_list("foo", "bar")], ["bar"]);
is_deeply([sort(pagespec_match_list("foo", "post/*"))], ["post/1", "post/2", "post/3"]);
is_deeply([pagespec_match_list("foo", "post/*", sort => "title", reverse => 1)],
	["post/3", "post/2", "post/1"]);
is_deeply([pagespec_match_list("foo", "post/*", sort => "title", num => 2)],
	["post/1", "post/2"]);
is_deeply([pagespec_match_list("foo", "post/*", sort => "title", num => 50)],
	["post/1", "post/2", "post/3"]);
is_deeply([pagespec_match_list("foo", "post/*", sort => "title",
                         limit => sub { $_[0] !~ /3/}) ],
	["post/1", "post/2"]);
my $r=eval { pagespec_match_list("foo", "beep") };
ok(eval { pagespec_match_list("foo", "beep") } == 0);
ok(! $@, "does not fail with error when unable to match anything");
eval { pagespec_match_list("foo", "this is not a legal pagespec!") };
ok($@, "fails with error when pagespec bad");
