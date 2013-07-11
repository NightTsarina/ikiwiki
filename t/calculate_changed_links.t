#!/usr/bin/perl
package IkiWiki;

use warnings;
use strict;
use Test::More tests => 5;

BEGIN { use_ok("IkiWiki"); }
BEGIN { use_ok("IkiWiki::Render"); }
%config=IkiWiki::defaultconfig();
$config{srcdir}=$config{destdir}="/dev/null";

%oldrenderedfiles=%pagectime=();
%pagesources=%pagemtime=%oldlinks=%links=%depends=%typedlinks=%oldtypedlinks=
%destsources=%renderedfiles=%pagecase=%pagestate=();

IkiWiki::checkconfig();

foreach my $page (qw(tags/a tags/b Reorder Add Remove TypeAdd TypeRemove)) {
	$pagesources{$page} = "$page.mdwn";
	$pagemtime{$page} = $pagectime{$page} = 1000000;
}

$oldlinks{Reorder} = [qw{tags/a tags/b}];
$links{Reorder} = [qw{tags/b tags/a}];

$oldlinks{Add} = [qw{tags/b}];
$links{Add} = [qw{tags/a tags/b}];

$oldlinks{Remove} = [qw{tags/a}];
$links{Remove} = [];

$oldlinks{TypeAdd} = [qw{tags/a tags/b}];
$links{TypeAdd} = [qw{tags/a tags/b}];
# This causes TypeAdd to be rebuilt, but isn't a backlink change, so it doesn't
# cause tags/b to be rebuilt.
$oldtypedlinks{TypeAdd}{tag} = { "tags/a" => 1 };
$typedlinks{TypeAdd}{tag} = { "tags/a" => 1, "tags/b" => 1 };

$oldlinks{TypeRemove} = [qw{tags/a tags/b}];
$links{TypeRemove} = [qw{tags/a tags/b}];
# This causes TypeRemove to be rebuilt, but isn't a backlink change, so it
# doesn't cause tags/b to be rebuilt.
$oldtypedlinks{TypeRemove}{tag} = { "tags/a" => 1 };
$typedlinks{TypeRemove}{tag} = { "tags/a" => 1, "tags/b" => 1 };

my $oldlink_targets = calculate_old_links([keys %pagesources], []);
is_deeply($oldlink_targets, {
		Reorder => { "tags/a" => "tags/a", "tags/b" => "tags/b" },
		Add => { "tags/b" => "tags/b" },
		Remove => { "tags/a" => "tags/a" },
		TypeAdd => { "tags/a" => "tags/a", "tags/b" => "tags/b" },
		TypeRemove => { "tags/a" => "tags/a", "tags/b" => "tags/b" },
	});
my ($backlinkchanged, $linkchangers) = calculate_changed_links([keys %pagesources], [], $oldlink_targets);

is_deeply($backlinkchanged, { "tags/a" => 1 });
is_deeply($linkchangers, { add => 1, remove => 1, typeadd => 1, typeremove => 1 });
