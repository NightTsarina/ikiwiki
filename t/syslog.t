#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 3;
use utf8;

BEGIN { use_ok("IkiWiki"); }

$IkiWiki::config{verbose} = 1;
$IkiWiki::config{syslog} = 1;
$IkiWiki::config{wikiname} = 'ascii';
is(debug('test'), '');
$IkiWiki::config{wikiname} = 'not ⒶSCII';
is(debug('test'), '');
