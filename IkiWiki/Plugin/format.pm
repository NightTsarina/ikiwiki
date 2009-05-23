#!/usr/bin/perl
package IkiWiki::Plugin::format;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "preprocess", id => "format", call => \&preprocess);
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
	elsif (exists $IkiWiki::hooks{htmlize}{$format}) {
		return IkiWiki::htmlize($params{page}, $params{destpage},
		                        $format, $text);
	}
	else {
		# Other plugins can register htmlizefallback
		# hooks to add support for page types
		# not suitable for htmlize. Try them until
		# one succeeds.
		my $ret;
		IkiWiki::run_hooks(htmlizefallback => sub {
			$ret=shift->($format, $text)
				unless defined $ret;
		});
		return $ret if defined $ret;

		error(sprintf(gettext("unsupported page format %s"), $format));
	}
}

1
