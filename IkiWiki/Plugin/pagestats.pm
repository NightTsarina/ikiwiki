#!/usr/bin/perl
#
# Produce page statistics in various forms.
#
# Currently supported:
#   cloud: produces statistics in the form of a del.icio.us-style tag cloud
#          (default)
#   table: produces a table with the number of backlinks for each page
#
# by Enrico Zini
package IkiWiki::Plugin::pagestats;

use warnings;
use strict;
use IkiWiki 3.00;

# Names of the HTML classes to use for the tag cloud
our @classes = ('smallestPC', 'smallPC', 'normalPC', 'bigPC', 'biggestPC' );

sub import {
	hook(type => "getsetup", id => "pagestats", call => \&getsetup);
	hook(type => "preprocess", id => "pagestats", call => \&preprocess);
}

sub getsetup () {
	return 
		plugin => {
			safe => 1,
			rebuild => undef,
			section => "widget",
		},
}

sub preprocess (@) {
	my %params=@_;
	$params{pages}="*" unless defined $params{pages};
	my $style = ($params{style} or 'cloud');

	# Backwards compatibility
	if (defined $params{show} && $params{show} =~ m/^\d+$/) {
		$params{limit} = $params{show};
		delete $params{show};
	}

	my %counts;
	my $max = 0;
	foreach my $page (pagespec_match_list($params{page}, $params{pages},
		                  # update when a displayed page is added/removed
	        	          deptype => deptype("presence"))) {
		use IkiWiki::Render;

		my @backlinks = IkiWiki::backlink_pages($page);

		if (exists $params{among}) {
			# only consider backlinks from the amoung pages
			@backlinks = pagespec_match_list(
				$params{page}, $params{among},
				# update whenever links on those pages change
				deptype => deptype("links"),
				list => \@backlinks
			);
		}
		else {
			# update when any page with links changes,
			# in case the links point to our displayed pages
			add_depends($params{page}, "*", deptype("links"));
		}

		$counts{$page} = scalar(@backlinks);
		$max = $counts{$page} if $counts{$page} > $max;
	}

	if (exists $params{limit}) {
		my $i=0;
		my %show;
		foreach my $key (sort { $counts{$b} <=> $counts{$a} } keys %counts) {
			last if ++$i > $params{limit};
			$show{$key}=$counts{$key};
		}
		%counts=%show;
	}

	if ($style eq 'table') {
		return "<table class='".(exists $params{class} ? $params{class} : "pageStats")."'>\n".
			join("\n", map {
				"<tr><td>".
				htmllink($params{page}, $params{destpage}, $_, noimageinline => 1).
				"</td><td>".$counts{$_}."</td></tr>"
			}
			sort { $counts{$b} <=> $counts{$a} } keys %counts).
			"\n</table>\n" ;
	}
	else {
		# In case of misspelling, default to a page cloud

		my $res;
		if ($style eq 'list') {
			$res = "<ul class='".(exists $params{class} ? $params{class} : "list")."'>\n";
		}
		else {
			$res = "<div class='".(exists $params{class} ? $params{class} : "pagecloud")."'>\n";
		}
		foreach my $page (sort keys %counts) {
			next unless $counts{$page} > 0;

			my $class = $classes[$counts{$page} * scalar(@classes) / ($max + 1)];
			
			$res.="<li>" if $style eq 'list';
			$res .= "<span class=\"$class\">".
			        htmllink($params{page}, $params{destpage}, $page).
			        "</span>\n";
			$res.="</li>" if $style eq 'list';

		}
		if ($style eq 'list') {
			$res .= "</ul>\n";
		}
		else {
			$res .= "</div>\n";
		}

		return $res;
	}
}

1
