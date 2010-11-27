#!/usr/bin/perl
package IkiWiki::Plugin::transient;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "transient",  call => \&getsetup);
	hook(type => "checkconfig", id => "transient", call => \&checkconfig);
	hook(type => "change", id => "transient", call => \&change);
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
	eval q{use Cwd 'abs_path'};
	error($@) if $@;
	$transientdir = abs_path($config{wikistatedir})."/transient";
	add_underlay($transientdir);
}

sub change (@) {
	foreach my $file (@_) {
		# if the corresponding file exists in the transient underlay
		# and isn't actually being used, we can get rid of it
		my $page = pagename($file);
		my $casualty = "$transientdir/$page.$config{default_pageext}";
		if (srcfile($file) ne $casualty && -e $casualty) {
			debug(sprintf(gettext("removing transient version of %s"), $page));
			IkiWiki::prune($casualty);
		}
	}
}

1;
