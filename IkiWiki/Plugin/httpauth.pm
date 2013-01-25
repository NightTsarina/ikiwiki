#!/usr/bin/perl
# HTTP basic auth plugin.
package IkiWiki::Plugin::httpauth;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "checkconfig", id => "httpauth", call => \&checkconfig);
	hook(type => "getsetup", id => "httpauth", call => \&getsetup);
	hook(type => "auth", id => "httpauth", call => \&auth);
	hook(type => "formbuilder_setup", id => "httpauth",
		call => \&formbuilder_setup);
	hook(type => "canedit", id => "httpauth", call => \&canedit,
		first => 1);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 0,
			section => "auth",
		},
		cgiauthurl => {
			type => "string",
			example => "http://example.com/wiki/auth/ikiwiki.cgi",
			description => "url to redirect to when authentication is needed",
			safe => 1,
			rebuild => 0,
		},
		httpauth_pagespec => {
			type => "pagespec",
			example => "!*/Discussion",
			description => "PageSpec of pages where only httpauth will be used for authentication",
			safe => 0,
			rebuild => 0,
		},
}

sub checkconfig () {
	if ($config{cgi} && defined $config{cgiauthurl} &&
	    keys %{$IkiWiki::hooks{auth}} < 2) {
		# There are no other auth hooks registered, so avoid
		# the normal signin form, and jump right to httpauth.
		require IkiWiki::CGI;
		inject(name => "IkiWiki::cgi_signin", call => sub ($$) {
			my $cgi=shift;
			redir_cgiauthurl($cgi, $cgi->query_string());
		});
	}
}
			
sub redir_cgiauthurl ($;@) {
	my $cgi=shift;

	IkiWiki::redirect($cgi, 
		@_ > 1 ? IkiWiki::cgiurl(cgiurl => $config{cgiauthurl}, @_)
		       : $config{cgiauthurl}."?@_"
	);
	exit;
}

sub auth ($$) {
	my $cgi=shift;
	my $session=shift;

	if (defined $cgi->remote_user()) {
		$session->param("name", $cgi->remote_user());
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
			# bounce thru cgiauthurl and then back to
			# the stored postsignin action
			redir_cgiauthurl($cgi, do => "postsignin");
		}
	}
}

sub canedit ($$$) {
	my $page=shift;
	my $cgi=shift;
	my $session=shift;

	if (! defined $cgi->remote_user() &&
	    (! defined $session->param("name") ||
             ! IkiWiki::userinfo_get($session->param("name"), "regdate")) &&
	    defined $config{httpauth_pagespec} &&
	    length $config{httpauth_pagespec} &&
	    defined $config{cgiauthurl} &&
	    pagespec_match($page, $config{httpauth_pagespec})) {
		return sub {
			# bounce thru cgiauthurl and back to edit action
			redir_cgiauthurl($cgi, $cgi->query_string());
		};
	}
	else {
		return undef;
	}
}

1
