#!/usr/bin/perl
#
# Produce a hierarchical map of links.
#
# by Alessandro Dotti Contra <alessandro@hyboria.org>
#
# Revision: 0.2
package IkiWiki::Plugin::map;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "map", call => \&getsetup);
	hook(type => "preprocess", id => "map", call => \&preprocess);
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
	
	# Needs to update whenever a page is added or removed (or in some
	# cases, when its content changes, if show= is specified).
	my $deptype=deptype(exists $params{show} ? "content" : "presence");
	
	my $common_prefix;

	# Get all the items to map.
	my %mapitems;
	foreach my $page (pagespec_match_list($params{page}, $params{pages},
					deptype => $deptype)) {
		if (exists $params{show} && 
		    exists $pagestate{$page} &&
		    exists $pagestate{$page}{meta}{$params{show}}) {
			$mapitems{$page}=$pagestate{$page}{meta}{$params{show}};
		}
		else {
			$mapitems{$page}='';
		}
		# Check for a common prefix.
		if (! defined $common_prefix) {
			$common_prefix=$page;
		}
		elsif (length $common_prefix &&
		       $page !~ /^\Q$common_prefix\E(\/|$)/) {
			my @a=split(/\//, $page);
			my @b=split(/\//, $common_prefix);
			$common_prefix="";
			while (@a && @b && $a[0] eq $b[0]) {
				if (length $common_prefix) {
					$common_prefix.="/";
				}
				$common_prefix.=shift(@a);
				shift @b;
			}
		}
	}
	
	# Common prefix should not be a page in the map.
	while (defined $common_prefix && length $common_prefix &&
	       exists $mapitems{$common_prefix}) {
		$common_prefix=IkiWiki::dirname($common_prefix);
	}

	# Create the map.
	my $parent="";
	my $indent=0;
	my $openli=0;
	my $addparent="";
	my $map = "<div class='map'>\n";

	if (! keys %mapitems) {
		# return empty div for empty map
		$map .= "</div>\n";
		return $map; 
	} 
	else {
		$map .= "<ul>\n";
	}

	foreach my $item (sort keys %mapitems) {
		my @linktext = (length $mapitems{$item} ? (linktext => $mapitems{$item}) : ());
		$item=~s/^\Q$common_prefix\E\///
			if defined $common_prefix && length $common_prefix;
		my $depth = ($item =~ tr/\//\//) + 1;
		my $baseitem=IkiWiki::dirname($item);
		while (length $parent && length $baseitem && $baseitem !~ /^\Q$parent\E(\/|$)/) {
			$parent=IkiWiki::dirname($parent);
			last if length $addparent && $baseitem =~ /^\Q$addparent\E(\/|$)/;
			$addparent="";
			$indent--;
			$map .= "</li>\n";
			if ($indent > 0) {
				$map .= "</ul>\n";
			}
		}
		while ($depth < $indent) {
			$indent--;
			$map .= "</li>\n";
			if ($indent > 0) {
				$map .= "</ul>\n";
			}
		}
		my @bits=split("/", $item);
		my $p="";
		$p.="/".shift(@bits) for 1..$indent;
		while ($depth > $indent) {
			$indent++;
			if ($indent > 1) {
				$map .= "<ul>\n";
			}
			if ($depth > $indent) {
				$p.="/".shift(@bits);
				$addparent=$p;
				$addparent=~s/^\///;
				$map .= "<li>"
					.htmllink($params{page}, $params{destpage},
						 "/".$common_prefix.$p, class => "mapparent",
						 noimageinline => 1)
					."\n";
				$openli=1;
			}
			else {
				$openli=0;
			}
		}
		$map .= "</li>\n" if $openli;
		$map .= "<li>"
			.htmllink($params{page}, $params{destpage}, 
				"/".$common_prefix."/".$item,
				@linktext,
				class => "mapitem", noimageinline => 1)
			."\n";
		$openli=1;
		$parent=$item;
	}
	while ($indent > 0) {
		$indent--;
		$map .= "</li>\n</ul>\n";
	}
	$map .= "</div>\n";
	return $map;
}

1
