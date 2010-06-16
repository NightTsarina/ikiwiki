#!/usr/bin/perl
package IkiWiki::Plugin::theme;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "theme", call => \&getsetup);
	hook(type => "checkconfig", id => "theme", call => \&checkconfig);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 0,
			section => "web",
		},
		theme => {
			type => "string",
			example => "actiontabs",
			description => "name of theme to enable",
			safe => 1,
			rebuild => 0,
		},
}

my $added=0;
sub checkconfig () {
	if (! $added && exists $config{theme} && $config{theme} =~ /^\w+$/) {
		add_underlay("themes/".$config{theme});
		$added=1;
	}
}

1
