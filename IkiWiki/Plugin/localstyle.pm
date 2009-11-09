#!/usr/bin/perl

package IkiWiki::Plugin::localstyle;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "localstyle", call => \&getsetup);
	hook(type => "pagetemplate", id => "localstyle", call => \&pagetemplate);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 1,
		},
}

sub pagetemplate (@) {
	my %params=@_;
	
	my $template=$params{template};
	
	if ($template->query(name => "local_css")) {
		my $best=bestlink($params{page}, 'local.css');
		if ($best) {
			$template->param(local_css => $best);
		}
	}
}

1
