#!/usr/bin/perl
# Provides a list of broken links.
package IkiWiki::Plugin::brokenlinks;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "brokenlinks", call => \&getsetup);
	hook(type => "preprocess", id => "brokenlinks", call => \&preprocess);
}

sub getsetup {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
}

sub preprocess (@) {
	my %params=@_;
	$params{pages}="*" unless defined $params{pages};
	
	# Needs to update whenever the links on a page change.
	add_depends($params{page}, $params{pages}, links => 1);
	
	my @broken;
	foreach my $link (keys %IkiWiki::brokenlinks) {
		next if $link =~ /.*\/\Q$config{discussionpage}\E/i && $config{discussion};

		my @pages;
		foreach my $page (@{$IkiWiki::brokenlinks{$link}}) {
			push @pages, $page
				if pagespec_match($page, $params{pages}, location => $params{page});
		}
		next unless @pages;

		my $page=$IkiWiki::brokenlinks{$link}->[0];
		push @broken, sprintf(gettext("%s from %s"),
			htmllink($page, $params{destpage}, $link, noimageinline => 1),
			join(", ", map {
				htmllink($params{page}, $params{destpage}, $_, 	noimageinline => 1)
			} @pages)
		);
	}
	
	return gettext("There are no broken links!") unless @broken;
	return "<ul>\n"
		.join("\n",
			map {
				"<li>$_</li>"
			}
			sort @broken)
		."</ul>\n";
}

1
