#!/usr/bin/perl
# Provides a list of pages no other page links to.
package IkiWiki::Plugin::orphans;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "orphans", call => \&getsetup);
	hook(type => "preprocess", id => "orphans", call => \&preprocess);
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
	
	# Needs to update whenever a link changes, on any page
	# since any page could link to one of the pages we're
	# considering as orphans.
	add_depends($params{page}, "*", deptype("links"));
	
	my @orphans=pagespec_match_list($params{page}, $params{pages},
		# update when orphans are added/removed
		deptype => deptype("presence"),
		filter => sub {
			my $page=shift;

			# Filter out pages that other pages link to.
			return 1 if IkiWiki::backlink_pages($page);

			# Toplevel index is assumed to never be orphaned.
			return 1 if $page eq 'index';

			# If the page has a link to some other page, it's
			# indirectly linked via that page's backlinks.
			return 1 if grep {
				length $_ &&
				($_ !~ /\/\Q$config{discussionpage}\E$/i || ! $config{discussion}) &&
				bestlink($page, $_) !~ /^(\Q$page\E|)$/ 
			} @{$links{$page}};
			
			return 0;
		},
	);
	
	return gettext("All pages have other pages linking to them.") unless @orphans;
	return "<ul>\n".
		join("\n",
			map {
				"<li>".
				htmllink($params{page}, $params{destpage}, $_,
					 noimageinline => 1).
				"</li>"
			} sort @orphans).
		"</ul>\n";
}

1
