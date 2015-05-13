#!/usr/bin/perl
# Ikiwiki email address as login
package IkiWiki::Plugin::emailauth;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "emailauth", "call" => \&getsetup);
	IkiWiki::loadplugin("loginselector");
	IkiWiki::Plugin::loginselector::register_login_plugin(
		"emailauth",
		\&email_setup,
		\&email_check_input,
		\&email_auth,
	);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 0,
			section => "auth",
		},
}

sub email_setup ($$) {
	my $q=shift;
	my $template=shift;

	return 1;
}

sub email_check_input ($) {
	my $cgi=shift;
	defined $cgi->param('do')
		&& $cgi->param("do") eq "signin"
		&& defined $cgi->param('Email_entry')
		&& length $cgi->param('Email_entry');
}

sub email_auth ($$$) {
	my $cgi=shift;
	my $session=shift;
	my $errordisplayer=shift;
	
	unless ($cgi->param('Email_entry') =~ /.\@./) {
		$errordisplayer->("Invalid email address.");
		return;
	}

	error "EMAIL AUTH";
}

1
