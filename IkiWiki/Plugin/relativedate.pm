#!/usr/bin/perl
package IkiWiki::Plugin::relativedate;

use warnings;
no warnings 'redefine';
use strict;
use IkiWiki 3.00;
use POSIX ();
use Encode;

sub import {
	add_underlay("javascript");
	hook(type => "getsetup", id => "relativedate", call => \&getsetup);
	hook(type => "format", id => "relativedate", call => \&format);
	inject(name => "IkiWiki::displaytime", call => \&mydisplaytime);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 1,
		},
}

sub format (@) {
        my %params=@_;

	if (! ($params{content}=~s!^(<body[^>]*>)!$1.include_javascript($params{page})!em)) {
		# no <body> tag, probably in preview mode
		$params{content}=include_javascript(undef).$params{content};
	}
	return $params{content};
}

sub include_javascript ($) {
	my $from=shift;
	
	return '<script src="'.urlto("ikiwiki/ikiwiki.js", $from).
		'" type="text/javascript" charset="utf-8"></script>'."\n".
		'<script src="'.urlto("ikiwiki/relativedate.js", $from).
		'" type="text/javascript" charset="utf-8"></script>';
}

sub mydisplaytime ($;$$) {
	my $time=shift;
	my $format=shift;
	my $pubdate=shift;

	# This needs to be in a form that can be parsed by javascript.
	# (Being fairly human readable is also nice, as it will be exposed
	# as the title if javascript is not available.)
	my $lc_time=POSIX::setlocale(&POSIX::LC_TIME);
	POSIX::setlocale(&POSIX::LC_TIME, "C");
	my $gmtime=decode_utf8(POSIX::strftime("%a, %d %b %Y %H:%M:%S %z",
			localtime($time)));
	POSIX::setlocale(&POSIX::LC_TIME, $lc_time);

	my $mid=' class="relativedate" title="'.$gmtime.'">'.
		IkiWiki::formattime($time, $format);

	if ($config{html5}) {
		return '<time datetime="'.IkiWiki::date_3339($time).'"'.
			($pubdate ? ' pubdate="pubdate"' : '').$mid.'</time>';
	}
	else {
		return '<span'.$mid.'</span>';
	}
}

1
