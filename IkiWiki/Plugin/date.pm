#!/usr/bin/perl
package IkiWiki::Plugin::date;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "date", call => \&getsetup);
	hook(type => "preprocess", id => "date", call => \&preprocess);
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
	my $str=shift;

	eval q{use Date::Parse};
	error $@ if $@;
	my $time = str2time($str);
	if (! defined $time) {
		error("unable to parse $str");
	}
	return displaytime($time);
}

1
