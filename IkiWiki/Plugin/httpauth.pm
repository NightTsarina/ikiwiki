#!/usr/bin/perl
# HTTP basic auth plugin.
package IkiWiki::Plugin::httpauth;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "httpauth", call => \&getsetup);
	hook(type => "auth", id => "httpauth", call => \&auth);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 0,
		},
		cgiauthurl => {
			type => "string",
			example => "http://example.com/wiki/auth/ikiwiki.cgi",
			description => "url to redirect to when authentication is needed",
			safe => 1,
			rebuild => 0,
		},
}

sub auth ($$) {
	my $cgi=shift;
	my $session=shift;

	if (defined $cgi->remote_user()) {
		$session->param("name", $cgi->remote_user());
	}
	elsif (defined $config{cgiauthurl}) {
		IkiWiki::redirect($cgi, $config{cgiauthurl}.'?'.$cgi->query_string());
		exit;
	}
}

1
