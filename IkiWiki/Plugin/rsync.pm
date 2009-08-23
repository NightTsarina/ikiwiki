#!/usr/bin/perl
package IkiWiki::Plugin::rsync;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "rsync", call => \&getsetup);
	hook(type => "checkconfig", id => "rsync", call => \&checkconfig);
	hook(type => "postrefresh", id => "rsync", call => \&postrefresh);
}

sub getsetup () {
	return
		plugin => {
			safe => 0,
			rebuild => 0,
		},
		rsync_command => {
			type => "string",
			example => "rsync -qa --delete /path/to/destdir/ user\@host:/path/to/docroot/",
			description => "command to upload regenerated pages to another host",
			safe => 0,
			rebuild => 0,
		},
}

sub checkconfig {
	if (! exists $config{rsync_command} ||
	    ! defined $config{rsync_command}) {
		error("Must specify rsync_command");
	}
}

sub postrefresh () {
	debug "in postrefresh hook, gonna run rsync";
	system $config{rsync_command};
	if ($? == -1) {
		error("failed to execute rsync_command: $!");
	} elsif ($? != 0) {
		error(sprintf("rsync_command exited %d", $? >> 8));
	}
}

1
