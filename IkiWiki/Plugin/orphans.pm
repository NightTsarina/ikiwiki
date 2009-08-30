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
		},
}

sub preprocess (@) {
	my %params=@_;
	$params{pages}="*" unless defined $params{pages};
	
	# Needs to update whenever a page is added or removed, so
	# register a dependency.
	add_depends($params{page}, $params{pages});
	
	my @orphans;
	foreach my $page (pagespec_match_list(
			[ grep { ! IkiWiki::backlink_pages($_) && $_ ne 'index' }
				keys %pagesources ],
			$params{pages}, location => $params{page})) {
		# If the page has a link to some other page, it's
		# indirectly linked to a page via that page's backlinks.
		next if grep { 
			length $_ &&
			($_ !~ /\/\Q$config{discussionpage}\E$/i || ! $config{discussion}) &&
			bestlink($page, $_) !~ /^(\Q$page\E|)$/ 
		} @{$links{$page}};
		push @orphans, $page;
	}
	
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
