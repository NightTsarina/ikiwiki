#!/usr/bin/perl
# Copyright © 2008-2011 Joey Hess
# Copyright © 2009-2011 Simon McVittie <http://smcv.pseudorandom.co.uk/>
# Licensed under the GNU GPL, version 2, or any later version published by the
# Free Software Foundation
package IkiWiki::Plugin::trail;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "trail", call => \&getsetup);
	hook(type => "needsbuild", id => "trail", call => \&needsbuild);
	hook(type => "preprocess", id => "trail", call => \&preprocess_trail, scan => 1);
	hook(type => "preprocess", id => "trailinline", call => \&preprocess_trailinline, scan => 1);
	hook(type => "preprocess", id => "trailitem", call => \&preprocess_trailitem, scan => 1);
	hook(type => "preprocess", id => "traillink", call => \&preprocess_traillink, scan => 1);
	hook(type => "pagetemplate", id => "trail", call => \&pagetemplate);
}

=head1 Page state

If a page C<$T> is a trail, then it can have

=over

=item * C<$pagestate{$T}{trail}{contents}>

Reference to an array of lists each containing either:

=over

=item * C<[link, "link"]>

A link specification, pointing to the same page that C<[[link]]> would select

=item * C<[pagespec, "posts/*", "age", 0]>

A match by pagespec; the third array element is the sort order and the fourth
is whether to reverse sorting

=back

=item * C<$pagestate{$T}{trail}{sort}>

A [[ikiwiki/pagespec/sorting]] order; if absent or undef, the trail is in
the order given by the links that form it

=item * C<$pagestate{$T}{trail}{circular}>

True if this trail is circular (i.e. going "next" from the last item is
allowed, and takes you back to the first)

=item * C<$pagestate{$T}{trail}{reverse}>

True if C<sort> is to be reversed.

=back

If a page C<$M> is a member of a trail C<$T>, then it has

=over

=item * C<$pagestate{$M}{trail}{item}{$T}[0]>

The page before this one in C<$T> at the last rebuild, or undef.

=item * C<$pagestate{$M}{trail}{item}{$T}[1]>

The page after this one in C<$T> at the last refresh, or undef.

=back

=cut

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
}

sub needsbuild (@) {
	my $needsbuild=shift;
	foreach my $page (keys %pagestate) {
		if (exists $pagestate{$page}{trail}) {
			if (exists $pagesources{$page} &&
			    grep { $_ eq $pagesources{$page} } @$needsbuild) {
				# Remove state, it will be re-added
				# if the preprocessor directive is still
				# there during the rebuild. {item} is the
				# only thing that's added for items, not
				# trails, and it's harmless to delete that -
				# the item is being rebuilt anyway.
				delete $pagestate{$page}{trail};
			}
		}
	}
	return $needsbuild;
}

my $scanned = 0;

sub preprocess_trail (@) {
	my %params = @_;

	# avoid collecting everything in the preprocess stage if we already
	# did in the scan stage
	if (defined wantarray) {
		return "" if $scanned;
	}
	else {
		$scanned = 1;
	}

	# trail members from a pagespec ought to be in some sort of order,
	# and path is a nice obvious default
	$params{sortthese} = 'path' unless exists $params{sortthese};
	$params{reversethese} = 'no' unless exists $params{reversethese};

	if (exists $params{circular}) {
		$pagestate{$params{page}}{trail}{circular} =
			IkiWiki::yesno($params{circular});
	}

	if (exists $params{sort}) {
		$pagestate{$params{page}}{trail}{sort} = $params{sort};
	}

	if (exists $params{reverse}) {
		$pagestate{$params{page}}{trail}{reverse} = $params{reverse};
	}

	if (exists $params{pages}) {
		push @{$pagestate{$params{page}}{trail}{contents}},
			["pagespec" => $params{pages}, $params{sortthese},
				IkiWiki::yesno($params{reversethese})];
	}

	if (exists $params{pagenames}) {
		my @list = map { [link =>  $_] } split ' ', $params{pagenames};
		push @{$pagestate{$params{page}}{trail}{contents}}, @list;
	}

	return "";
}

sub preprocess_trailinline (@) {
	my %params = @_;

	if (exists $params{sort}) {
		$params{sortthese} = $params{sort};
		delete $params{sort};
	}
	else {
		# sort in the same order as [[plugins/inline]]'s default
		$params{sortthese} = 'age';
	}

	if (exists $params{reverse}) {
		$params{reversethese} = $params{reverse};
		delete $params{reverse};
	}

	if (exists $params{trailsort}) {
		$params{sort} = $params{trailsort};
	}

	if (exists $params{trailreverse}) {
		$params{reverse} = $params{trailreverse};
	}

	if (defined wantarray) {
		scalar preprocess_trail(%params);

		if (IkiWiki->can("preprocess_inline")) {
			return IkiWiki::preprocess_inline(@_);
		}
		else {
			error("trailinline directive requires the inline plugin");
		}
	}
	else {
		preprocess_trail(%params);
	}
}

sub preprocess_trailitem (@) {
	my $link = shift;
	shift;

	# avoid collecting everything in the preprocess stage if we already
	# did in the scan stage
	if (defined wantarray) {
		return "" if $scanned;
	}
	else {
		$scanned = 1;
	}

	my %params = @_;
	my $trail = $params{page};

	$link = linkpage($link);

	add_link($params{page}, $link, 'trail');
	push @{$pagestate{$params{page}}{trail}{contents}}, [link => $link];

	return "";
}

sub preprocess_traillink (@) {
	my $link = shift;
	shift;

	my %params = @_;
	my $trail = $params{page};

	$link =~ qr{
			(?:
				([^\|]+)	# 1: link text
				\|		# followed by |
			)?			# optional

			(.+)			# 2: page to link to
		}x;

	my $linktext = $1;
	$link = linkpage($2);

	add_link($params{page}, $link, 'trail');

	# avoid collecting everything in the preprocess stage if we already
	# did in the scan stage
	my $already;
	if (defined wantarray) {
		$already = $scanned;
	}
	else {
		$scanned = 1;
	}

	push @{$pagestate{$params{page}}{trail}{contents}}, [link => $link] unless $already;

	if (defined $linktext) {
		$linktext = pagetitle($linktext);
	}

	if (exists $params{text}) {
		$linktext = $params{text};
	}

	if (defined $linktext) {
		return htmllink($trail, $params{destpage},
			$link, linktext => $linktext);
	}

	return htmllink($trail, $params{destpage}, $link);
}

# trail => [member1, member2]
my %trail_to_members;
# member => { trail => [prev, next] }
# e.g. if %trail_to_members = (
#	trail1 => ["member1", "member2"],
#	trail2 => ["member0", "member1"],
# )
#
# then $member_to_trails{member1} = {
#	trail1 => [undef, "member2"],
#	trail2 => ["member0", undef],
# }
my %member_to_trails;

# member => 1
my %rebuild_trail_members;

sub trails_differ {
	my ($old, $new) = @_;

	foreach my $trail (keys %$old) {
		if (! exists $new->{$trail}) {
			return 1;
		}
		my ($old_p, $old_n) = @{$old->{$trail}};
		my ($new_p, $new_n) = @{$new->{$trail}};
		$old_p = "" unless defined $old_p;
		$old_n = "" unless defined $old_n;
		$new_p = "" unless defined $new_p;
		$new_n = "" unless defined $new_n;
		if ($old_p ne $new_p) {
			return 1;
		}
		if ($old_n ne $new_n) {
			return 1;
		}
	}

	foreach my $trail (keys %$new) {
		if (! exists $old->{$trail}) {
			return 1;
		}
	}

	return 0;
}

my $done_prerender = 0;

my %origsubs;

sub prerender {
	return if $done_prerender;

	$origsubs{render_backlinks} = \&IkiWiki::render_backlinks;
	inject(name => "IkiWiki::render_backlinks", call => \&render_backlinks);

	%trail_to_members = ();
	%member_to_trails = ();

	foreach my $trail (keys %pagestate) {
		next unless exists $pagestate{$trail}{trail}{contents};

		my $members = [];
		my @contents = @{$pagestate{$trail}{trail}{contents}};

		foreach my $c (@contents) {
			if ($c->[0] eq 'pagespec') {
				push @$members, pagespec_match_list($trail,
					$c->[1], sort => $c->[2],
					reverse => $c->[3]);
			}
			elsif ($c->[0] eq 'link') {
				my $best = bestlink($trail, $c->[1]);
				push @$members, $best if length $best;
			}
		}

		if (defined $pagestate{$trail}{trail}{sort}) {
			# re-sort
			@$members = pagespec_match_list($trail, 'internal(*)',
				list => $members,
				sort => $pagestate{$trail}{trail}{sort});
		}

		if (IkiWiki::yesno $pagestate{$trail}{trail}{reverse}) {
			@$members = reverse @$members;
		}

		# uniquify
		my %seen;
		my @tmp;
		foreach my $member (@$members) {
			push @tmp, $member unless $seen{$member};
			$seen{$member} = 1;
		}
		$members = [@tmp];

		for (my $i = 0; $i <= $#$members; $i++) {
			my $member = $members->[$i];
			my $prev;
			$prev = $members->[$i - 1] if $i > 0;
			my $next = $members->[$i + 1];

			add_depends($member, $trail);

			$member_to_trails{$member}{$trail} = [$prev, $next];
		}

		if ((scalar @$members) > 1 && $pagestate{$trail}{trail}{circular}) {
			$member_to_trails{$members->[0]}{$trail}[0] = $members->[$#$members];
			$member_to_trails{$members->[$#$members]}{$trail}[1] = $members->[0];
		}

		$trail_to_members{$trail} = $members;
	}

	foreach my $member (keys %pagestate) {
		if (exists $pagestate{$member}{trail}{item} &&
			! exists $member_to_trails{$member}) {
			$rebuild_trail_members{$member} = 1;
			delete $pagestate{$member}{trailitem};
		}
	}

	foreach my $member (keys %member_to_trails) {
		if (! exists $pagestate{$member}{trail}{item}) {
			$rebuild_trail_members{$member} = 1;
		}
		else {
			if (trails_differ($pagestate{$member}{trail}{item},
					$member_to_trails{$member})) {
				$rebuild_trail_members{$member} = 1;
			}
		}

		$pagestate{$member}{trail}{item} = $member_to_trails{$member};
	}

	$done_prerender = 1;
}

# This is called at about the right time that we can hijack it to render
# extra pages.
sub render_backlinks ($) {
	my $blc = shift;

	foreach my $member (keys %rebuild_trail_members) {
		next unless exists $pagesources{$member};

		IkiWiki::render($pagesources{$member}, sprintf(gettext("building %s, its previous or next page has changed"), $member));
	}

	$origsubs{render_backlinks}($blc);
}

sub title_of ($) {
	my $page = shift;
	if (defined ($pagestate{$page}{meta}{title})) {
		return $pagestate{$page}{meta}{title};
	}
	return pagetitle(IkiWiki::basename($page));
}

my $recursive = 0;

sub pagetemplate (@) {
	my %params = @_;
	my $page = $params{page};
	my $template = $params{template};

	if ($template->query(name => 'trails') && ! $recursive) {
		prerender();

		$recursive = 1;
		my $inner = template("trails.tmpl", blind_cache => 1);
		IkiWiki::run_hooks(pagetemplate => sub {
				shift->(%params, template => $inner)
			});
		$template->param(trails => $inner->output);
		$recursive = 0;
	}

	if ($template->query(name => 'trailloop')) {
		prerender();

		my @trails;

		# sort backlinks by page name to have a consistent order
		foreach my $trail (sort keys %{$member_to_trails{$page}}) {

			my $members = $trail_to_members{$trail};
			my ($prev, $next) = @{$member_to_trails{$page}{$trail}};
			my ($prevurl, $nexturl, $prevtitle, $nexttitle);

			if (defined $prev) {
				add_depends($params{destpage}, $prev);
				$prevurl = urlto($prev, $page);
				$prevtitle = title_of($prev);
			}

			if (defined $next) {
				add_depends($params{destpage}, $next);
				$nexturl = urlto($next, $page);
				$nexttitle = title_of($next);
			}

			push @trails, {
				prevpage => $prev,
				prevtitle => $prevtitle,
				prevurl => $prevurl,
				nextpage => $next,
				nexttitle => $nexttitle,
				nexturl => $nexturl,
				trailpage => $trail,
				trailtitle => title_of($trail),
				trailurl => urlto($trail, $page),
			};
		}

		$template->param(trailloop => \@trails);
	}
}

1;
