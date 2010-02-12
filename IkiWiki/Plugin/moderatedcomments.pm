#!/usr/bin/perl
package IkiWiki::Plugin::moderatedcomments;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "moderatedcomments",  call => \&getsetup);
	hook(type => "checkcontent", id => "moderatedcomments", call => \&checkcontent);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 0,
			section => "auth",
		},
		moderate_users => {
			type => 'boolean',
			example => 1,
			description => 'Moderate comments of logged-in users?',
			safe => 1,
			rebuild => 0,
		},
}

sub checkcontent (@) {
	my %params=@_;
	
	# only handle comments	
	return undef unless pagespec_match($params{page}, "postcomment(*)",
	                	location => $params{page});

	# admins and maybe users can comment w/o moderation
	my $session=$params{session};
	my $user=$session->param("name") if $session;
	return undef if defined $user && (IkiWiki::is_admin($user) ||
		(exists $config{moderate_users} && ! $config{moderate_users}));

	return gettext("comment needs moderation");
}

1
