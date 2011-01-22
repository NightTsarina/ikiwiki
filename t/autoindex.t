#!/usr/bin/perl
package IkiWiki;

use warnings;
use strict;
use Test::More tests => 22;

BEGIN { use_ok("IkiWiki"); }
BEGIN { use_ok("IkiWiki::Render"); }
BEGIN { use_ok("IkiWiki::Plugin::aggregate"); }
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

# a directory containing only an internal page shouldn't be indexed
$pagesources{"has_internal/internal"} = "has_internal/internal._aggregated";
$pagemtime{"has_internal/internal"} = 123456789;
$pagectime{"has_internal/internal"} = 123456789;
writefile("has_internal/internal._aggregated", "t/tmp", "this page is internal");

# a directory containing only an attachment should be indexed
$pagesources{"attached/pie.jpg"} = "attached/pie.jpg";
$pagemtime{"attached/pie.jpg"} = 123456789;
$pagectime{"attached/pie.jpg"} = 123456789;
writefile("attached/pie.jpg", "t/tmp", "I lied, this isn't a real JPEG");

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

# a directory containing only an internal page shouldn't be indexed
ok(! exists $wikistate{autoindex}{deleted}{has_internal});
ok(! -f "t/tmp/has_internal.mdwn");

# this page was re-created, so it drops off the radar
ok(! exists $wikistate{autoindex}{deleted}{reinstated});
ok(! -f "t/tmp/reinstated.mdwn");

# needs creating
ok(! exists $wikistate{autoindex}{deleted}{tags});
ok(-s "t/tmp/tags.mdwn");

# needs creating because of an attachment
ok(! exists $wikistate{autoindex}{deleted}{attached});
ok(-s "t/tmp/attached.mdwn");

1;
