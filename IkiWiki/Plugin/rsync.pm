#!/usr/bin/perl
package IkiWiki::Plugin::rsync;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "rsync", call => \&getsetup);
	hook(type => "rendered", id => "rsync", call => \&postrefresh);
	hook(type => "delete", id => "rsync", call => \&postrefresh);
}

sub getsetup () {
	return
		plugin => {
			safe => 0,
			rebuild => 0,
		},
		rsync_command => {
			type => "string",
			example => "rsync -qa --delete . user\@host:/path/to/docroot/",
			description => "command to run to sync updated pages",
			safe => 0,
			rebuild => 0,
		},
}

my $ran=0;

sub postrefresh () {
	if (defined $config{rsync_command} && ! $ran) {
		$ran=1;
		chdir($config{destdir}) || error("chdir: $!");
		system $config{rsync_command};
		if ($? == -1) {
			warn(sprintf(gettext("failed to execute rsync_command: %s"), $!))."\n";
		}
		elsif ($? != 0) {
			warn(sprintf(gettext("rsync_command exited %d"), $? >> 8))."\n";
		}
	}
}

1
