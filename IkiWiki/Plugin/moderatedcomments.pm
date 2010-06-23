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
		moderate_pagespec => {
			type => 'pagespec',
			example => '*',
			description => 'PageSpec matching users or comment locations to moderate',
			link => 'ikiwiki/PageSpec',
			safe => 1,
			rebuild => 0,
		},
}

sub checkcontent (@) {
	my %params=@_;
	
	# only handle comments	
	return undef unless pagespec_match($params{page}, "postcomment(*)",
	                	location => $params{page});
	
	# backwards compatability
	if (exists $config{moderate_users} &&
	    ! exists $config{moderate_pagespec}) {
		$config{moderate_pagespec} = $config{moderate_users}
			? "!admin()"
			: "!user(*)";
	}

	# default is to moderate all except admins
	if (! exists $config{moderate_pagespec}) {
		$config{moderate_pagespec}="!admin()";
	}

	my $session=$params{session};
	my $user=$session->param("name");
	if (pagespec_match($params{page}, $config{moderate_pagespec},
			location => $params{page},
			(defined $user ? (user => $user) : ()),
			(defined $session->remote_addr() ? (ip => $session->remote_addr()) : ()),
	)) {
		return gettext("comment needs moderation");
	}
	else {
		return undef;
	}
}

1
