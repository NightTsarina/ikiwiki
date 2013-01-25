#!/usr/bin/perl
package IkiWiki::Plugin::opendiscussion;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "opendiscussion", call => \&getsetup);
	hook(type => "canedit", id => "opendiscussion", call => \&canedit,
		first => 1);
}

sub getsetup () {
	return 
		plugin => {
			safe => 1,
			rebuild => 0,
			section => "auth",
		},
}

sub canedit ($$) {
	my $page=shift;
	my $cgi=shift;
	my $session=shift;

	return "" if $config{discussion} && $page=~/(\/|^)\Q$config{discussionpage}\E$/i;
	return "" if pagespec_match($page, "postcomment(*)");
	return undef;
}

1
