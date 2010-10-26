#!/usr/bin/perl
package IkiWiki::Plugin::format;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "preprocess", id => "format", call => \&preprocess);
	hook(type => "getsetup",   id => "format", call => \&getsetup);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
			section => "widget",
		},
}

sub preprocess (@) {
	my %params=@_;
	my $format=shift;
	shift;
	my $text=IkiWiki::preprocess($params{page}, $params{destpage}, shift);
	shift;

	if (! defined $format || ! defined $text) {
		error(gettext("must specify format and text"));
	}
		
	# Other plugins can register htmlizeformat hooks to add support
	# for page types not suitable for htmlize, or that need special
	# processing when included via format. Try them until one succeeds.
	my $ret;
	IkiWiki::run_hooks(htmlizeformat => sub {
		$ret=shift->($format, $text)
			unless defined $ret;
	});

	if (defined $ret) {
		return $ret;
	}
	elsif (exists $IkiWiki::hooks{htmlize}{$format}) {
		return IkiWiki::htmlize($params{page}, $params{destpage},
		                        $format, $text);
	}
	else {
		error(sprintf(gettext("unsupported page format %s"), $format));
	}
}

1
