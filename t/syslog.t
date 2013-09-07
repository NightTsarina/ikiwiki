#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 5;
use utf8;

BEGIN { use_ok("IkiWiki"); }

$IkiWiki::config{verbose} = 1;
$IkiWiki::config{syslog} = 1;

$IkiWiki::config{wikiname} = 'ASCII';
is(debug('test'), '', 'plain ASCII syslog');
$IkiWiki::config{wikiname} = 'not ⒶSCII';
is(debug('test'), '', 'UTF8 syslog');
my $orig = $IkiWiki::config{wikiname};
is(debug('test'), '', 'check for idempotency');
is($IkiWiki::config{wikiname}, $orig, 'unchanged config');
