#!/usr/bin/perl
# quick HTML heading id adder by Paul Wise
package IkiWiki::Plugin::headinganchors;

use warnings;
use strict;
use IkiWiki 3.00;
use URI::Escape;

sub import {
	hook(type => "getsetup", id => "headinganchors", call => \&getsetup);
	hook(type => "sanitize", id => "headinganchors", call => \&headinganchors);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
			section => "widget",
		},
}

sub text_to_anchor {
	my $str = shift;
	$str =~ s/^\s+//;
	$str =~ s/\s+$//;
	$str =~ s/\s/_/g;
	$str =~ s/"//g;
	$str =~ s/^[^a-zA-Z]/z-/; # must start with an alphabetical character
	$str = uri_escape_utf8($str);
	$str =~ s/%/./g;
	return $str;
}

sub headinganchors (@) {
	my %params=@_;
	my $content=$params{content};
	$content=~s{<h([0-9])>([^>]*)</h([0-9])>}{'<h'.$1.' id="'.text_to_anchor($2).'">'.$2.'</h'.$3.'>'}gie;
	return $content;
}

1
