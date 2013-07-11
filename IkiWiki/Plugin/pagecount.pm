#!/usr/bin/perl
package IkiWiki::Plugin::pagecount;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "pagecount", call => \&getsetup);
	hook(type => "preprocess", id => "pagecount", call => \&preprocess);
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
	my $pages=defined $params{pages} ? $params{pages} : "*";
	
	# Just get a list of all the pages, and count the items in it.
	# Use a presence dependency to only update when pages are added
	# or removed.

	if ($pages eq '*') {
		# optimisation to avoid needing to try matching every page
		add_depends($params{page}, $pages, deptype("presence"));
		return scalar keys %pagesources;
	}

	return scalar pagespec_match_list($params{page}, $pages,
		deptype => deptype("presence"));
}

1
