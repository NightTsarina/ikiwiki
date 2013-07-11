#!/usr/bin/perl
package IkiWiki;

use warnings;
use strict;
use Test::More tests => 24;

BEGIN { use_ok("IkiWiki"); }
BEGIN { use_ok("IkiWiki::Render"); }
BEGIN { use_ok("IkiWiki::Plugin::mdwn"); }
BEGIN { use_ok("IkiWiki::Plugin::tag"); }

ok(! system("rm -rf t/tmp; mkdir t/tmp"));

$config{srcdir} = 't/tmp';
$config{underlaydir} = 't/tmp';
$config{templatedir} = 'templates';
$config{usedirs} = 1;
$config{htmlext} = 'html';
$config{wiki_file_chars} = "-[:alnum:]+/.:_";
$config{userdir} = "users";
$config{tagbase} = "tags";
$config{tag_autocreate} = 1;
$config{tag_autocreate_commit} = 0;
$config{default_pageext} = "mdwn";
$config{wiki_file_prune_regexps} = [qr/^\./];
$config{underlaydirbase} = '.';

is(checkconfig(), 1);

%oldrenderedfiles=%pagectime=();
%pagesources=%pagemtime=%oldlinks=%links=%depends=%typedlinks=%oldtypedlinks=
%destsources=%renderedfiles=%pagecase=%pagestate=();

foreach my $page (qw(tags/numbers tags/letters one two alpha beta)) {
	$pagesources{$page} = "$page.mdwn";
	$pagemtime{$page} = $pagectime{$page} = 1000000;
	writefile("$page.mdwn", "t/tmp", "your ad here");
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

# emulate preprocessing [[!tag numbers primes lucky]] on page "seven", causing
# the "numbers" and "primes" tag pages to be auto-created
IkiWiki::Plugin::tag::preprocess_tag(page => "seven", numbers => undef, primes => undef, lucky => undef);
is($autofiles{"tags/lucky.mdwn"}{plugin}, "tag");
is($autofiles{"tags/numbers.mdwn"}{plugin}, "tag");
is($autofiles{"tags/primes.mdwn"}{plugin}, "tag");
is_deeply([sort keys %autofiles], [qw(tags/lucky.mdwn tags/numbers.mdwn tags/primes.mdwn)]);

ok(!-e "t/tmp/tags/lucky.mdwn");
my (%pages, @del);
IkiWiki::gen_autofile("tags/lucky.mdwn", \%pages, \@del);
ok(! -s "t/tmp/tags/lucky.mdwn");
ok(-s "t/tmp/.ikiwiki/transient/tags/lucky.mdwn");
is_deeply(\%pages, {"t/tmp/tags/lucky" => 1});
is_deeply(\@del, []);

# generating an autofile that already exists does nothing
%pages = @del = ();
IkiWiki::gen_autofile("tags/numbers.mdwn", \%pages, \@del);
is_deeply(\%pages, {});
is_deeply(\@del, []);

# generating an autofile that we just deleted does nothing
%pages = ();
@del = ('tags/primes.mdwn');
IkiWiki::gen_autofile("tags/primes.mdwn", \%pages, \@del);
is_deeply(\%pages, {});
is_deeply(\@del, ['tags/primes.mdwn']);


# cleanup
ok(! system("rm -rf t/tmp"));

1;
