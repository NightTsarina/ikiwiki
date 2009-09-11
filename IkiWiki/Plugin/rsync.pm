#!/usr/bin/perl
package IkiWiki::Plugin::rsync;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "rsync", call => \&getsetup);
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
			description => "unattended command to upload regenerated pages",
			safe => 0,
			rebuild => 0,
		},
}

sub postrefresh () {
	if (defined $config{rsync_command}) {
		system $config{rsync_command};
		if ($? == -1) {
			warn("failed to execute rsync_command: $!");
		} elsif ($? != 0) {
			warn(sprintf("rsync_command exited %d", $? >> 8));
		}
	}
}

1
