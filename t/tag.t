#!/usr/bin/perl
package IkiWiki;

use warnings;
use strict;
use Test::More tests => 7;

BEGIN { use_ok("IkiWiki"); }
BEGIN { use_ok("IkiWiki::Plugin::tag"); }

ok(! system("rm -rf t/tmp; mkdir t/tmp"));

$config{userdir} = "users";
$config{tagbase} = "tags";

%oldrenderedfiles=%pagectime=();
%pagesources=%pagemtime=%oldlinks=%links=%depends=%typedlinks=%oldtypedlinks=
%destsources=%renderedfiles=%pagecase=%pagestate=();

foreach my $page (qw(tags/numbers tags/letters one two alpha beta)) {
	$pagesources{$page} = "$page.mdwn";
	$pagemtime{$page} = $pagectime{$page} = 1000000;
}

$links{one}=[qw(tags/numbers alpha tags/letters)];
$links{two}=[qw(tags/numbers)];
$links{alpha}=[qw(tags/letters one)];
$links{beta}=[qw(tags/letters)];
$typedlinks{one}={tag => {"tags/numbers" => 1 }};
$typedlinks{two}={tag => {"tags/numbers" => 1 }};
$typedlinks{alpha}={tag => {"tags/letters" => 1 }};
$typedlinks{beta}={tag => {"tags/letters" => 1 }};

ok(pagespec_match("one", "tagged(numbers)"));
ok(!pagespec_match("two", "tagged(alpha)"));
ok(pagespec_match("one", "link(tags/numbers)"));
ok(pagespec_match("one", "link(alpha)"));

1;
