#!/usr/bin/perl
package IkiWiki::Plugin::transient;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "transient",  call => \&getsetup);
	hook(type => "checkconfig", id => "transient", call => \&checkconfig);
	hook(type => "rendered", id => "transient", call => \&rendered);
}

sub getsetup () {
	return
		plugin => {
			# this plugin is safe but only makes sense as a
			# dependency; similarly, it needs a rebuild but
			# only if something else does
			safe => 0,
			rebuild => 0,
		},
}

our $transientdir;

sub checkconfig () {
	if (defined $config{wikistatedir}) {
		$transientdir = $config{wikistatedir}."/transient";
		# add_underlay treats relative underlays as relative to the installed
		# location, not the cwd. That's not what we want here.
		IkiWiki::add_literal_underlay($transientdir);
	}
}

sub rendered (@) {
	foreach my $file (@_) {
		# If the corresponding file exists in the transient underlay
		# and isn't actually being used, we can get rid of it.
		# Assume that the file that just changed has the same extension
		# as the obsolete transient version: this'll be true for web
		# edits, and avoids invoking File::Find.
		my $casualty = "$transientdir/$file";
		if (srcfile($file) ne $casualty && -e $casualty) {
			debug(sprintf(gettext("removing transient version of %s"), $file));
			IkiWiki::prune($casualty);
		}
	}
}

1;
