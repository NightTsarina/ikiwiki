#!/usr/bin/perl
# HTTP basic auth plugin.
package IkiWiki::Plugin::httpauth;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "httpauth", call => \&getsetup);
	hook(type => "auth", id => "httpauth", call => \&auth);
	hook(type => "formbuilder_setup", id => "httpauth",
		call => \&formbuilder_setup);
	hook(type => "canedit", id => "httpauth", call => \&canedit);
	hook(type => "pagetemplate", id => "httpauth", call => \&pagetemplate);
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
		httpauth_pagespec => {
			type => "pagespec",
			example => "!*/Discussion",
			description => "PageSpec of pages where only httpauth will be used for authentication",
			safe => 0,
			rebuild => 0,
		},
}
			
sub redir_cgiauthurl ($;@) {
	my $cgi=shift;

	IkiWiki::redirect($cgi, 
		IkiWiki::cgiurl(cgiurl => $config{cgiauthurl}, @_));
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

sub need_httpauth_pagespec () {
	return defined $config{httpauth_pagespec} &&
	       length $config{httpauth_pagespec} &&
	       defined $config{cgiauthurl};
}

sub test_httpauth_pagespec ($) {
	my $page=shift;

	pagespec_match($page, $config{httpauth_pagespec});
}

sub canedit ($$$) {
	my $page=shift;
	my $cgi=shift;
	my $session=shift;

	if (! defined $cgi->remote_user() &&
	    need_httpauth_pagespec() &&
    	    ! test_httpauth_pagespec($page)) {
		return sub {
			IkiWiki::redirect($cgi, 
				$config{cgiauthurl}.'?'.$cgi->query_string());
			exit;
		};
	}
	else {
		return undef;
	}
}

sub pagetemplate (@_) {
	my %params=@_;
	my $template=$params{template};

	if ($template->param("editurl") &&
	    need_httpauth_pagespec() &&
	    test_httpauth_pagespec($params{page})) {
		# go directly to cgiauthurl when editing a page matching
		# the pagespec
		$template->param(editurl => IkiWiki::cgiurl(
			cgiurl => $config{cgiauthurl},
			do => "edit", page => $params{page}));
	}
}

1
