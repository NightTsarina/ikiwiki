#!/usr/bin/perl
package IkiWiki;

use warnings;
use strict;
use Test::More tests => 17;

BEGIN { use_ok("IkiWiki"); }
BEGIN { use_ok("IkiWiki::Render"); }
BEGIN { use_ok("IkiWiki::Plugin::autoindex"); }
BEGIN { use_ok("IkiWiki::Plugin::html"); }
BEGIN { use_ok("IkiWiki::Plugin::mdwn"); }

ok(! system("rm -rf t/tmp; mkdir t/tmp"));

$config{verbose} = 1;
$config{srcdir} = 't/tmp';
$config{underlaydir} = 't/tmp';
$config{underlaydirbase} = '.';
$config{templatedir} = 'templates';
$config{usedirs} = 1;
$config{htmlext} = 'html';
$config{wiki_file_chars} = "-[:alnum:]+/.:_";
$config{userdir} = "users";
$config{tagbase} = "tags";
$config{default_pageext} = "mdwn";
$config{wiki_file_prune_regexps} = [qr/^\./];

is(checkconfig(), 1);

%oldrenderedfiles=%pagectime=();
%pagesources=%pagemtime=%oldlinks=%links=%depends=%typedlinks=%oldtypedlinks=
%destsources=%renderedfiles=%pagecase=%pagestate=();

# pages that (we claim) were deleted in an earlier pass
$wikistate{autoindex}{deleted}{deleted} = 1;
$wikistate{autoindex}{deleted}{expunged} = 1;
$wikistate{autoindex}{deleted}{reinstated} = 1;

foreach my $page (qw(tags/numbers deleted/bar reinstated reinstated/foo gone/bar)) {
	# we use a non-default extension for these, so they're distinguishable
	# from programmatically-created pages
	$pagesources{$page} = "$page.html";
	$pagemtime{$page} = $pagectime{$page} = 1000000;
	writefile("$page.html", "t/tmp", "your ad here");
}

# "gone" disappeared just before this refresh pass so it still has a mtime
$pagemtime{gone} = $pagectime{gone} = 1000000;

IkiWiki::Plugin::autoindex::refresh();

# these pages are still on record as having been deleted, because they have
# a reason to be re-created
is($wikistate{autoindex}{deleted}{deleted}, 1);
is($wikistate{autoindex}{deleted}{gone}, 1);
ok(! -f "t/tmp/deleted.mdwn");
ok(! -f "t/tmp/gone.mdwn");

# this page does not exist and has no reason to be re-created, so we forget
# about it - it will be re-created if it gains sub-pages
ok(! exists $wikistate{autoindex}{deleted}{expunged});
ok(! -f "t/tmp/expunged.mdwn");

# this page was re-created, so it drops off the radar
ok(! exists $wikistate{autoindex}{deleted}{reinstated});
ok(! -f "t/tmp/reinstated.mdwn");

# needs creating
ok(! exists $wikistate{autoindex}{deleted}{tags});
ok(-s "t/tmp/tags.mdwn");

1;
