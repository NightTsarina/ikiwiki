#!/usr/bin/perl
# HTTP basic auth plugin.
package IkiWiki::Plugin::httpauth;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "httpauth", call => \&getsetup);
	hook(type => "auth", id => "httpauth", call => \&auth);
	hook(type => "canedit", id => "httpauth", call => \&canedit,
		last => 1);
	hook(type => "formbuilder_setup", id => "httpauth",
		call => \&formbuilder_setup);
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
			
sub redir_cgiauthurl ($$) {
	my $cgi=shift;
	my $params=shift;

	IkiWiki::redirect($cgi, $config{cgiauthurl}.'?'.$params);
	exit;
}

sub auth ($$) {
	my $cgi=shift;
	my $session=shift;

	if (defined $cgi->remote_user()) {
		$session->param("name", $cgi->remote_user());
	}
}

sub canedit ($$$) {
	my $page=shift;
	my $cgi=shift;
	my $session=shift;

	if (! defined $cgi->remote_user() && defined $config{cgiauthurl}) {
		return sub { redir_cgiauthurl($cgi, $cgi->query_string()) };
	}
	else {
		return undef;
	}
}

sub formbuilder_setup (@) {
	my %params=@_;

	my $form=$params{form};
	my $session=$params{session};
	my $cgi=$params{cgi};
	my $buttons=$params{buttons};

	if ($form->title eq "signin" &&
	    ! defined $cgi->remote_user() && defined $config{cgiauthurl}) {
		my $button_text="Login with HTTP auth";
		push @$buttons, $button_text;

		if ($form->submitted && $form->submitted eq $button_text) {
			redir_cgiauthurl($cgi, "do=postsignin");
			exit;
		}
	}
}

1
