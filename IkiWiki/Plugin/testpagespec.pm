#!/usr/bin/perl
package IkiWiki::Plugin::testpagespec;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "testpagespec", call => \&getsetup);
	hook(type => "preprocess", id => "testpagespec", call => \&preprocess);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
			section => "special-purpose",
		},
}

sub preprocess (@) {
	my %params=@_;
	
	foreach my $param (qw{match pagespec}) {
		if (! exists $params{$param}) {
			error sprintf(gettext("%s parameter is required"), $param);
		}
	}

	add_depends($params{page}, $params{pagespec});
	
	my $ret=pagespec_match($params{match}, $params{pagespec}, 
			location => $params{page});
	if ($ret) {
		return "match: $ret";
	}
	else {
		return "no match: $ret";
	}
}

1
