#!/usr/bin/perl
package IkiWiki::Plugin::recentchangesdiff;

use warnings;
use strict;
use IkiWiki 3.00;
use HTML::Entities;

my $maxlines=200;

sub import {
	add_underlay("javascript");
	hook(type => "getsetup", id => "recentchangesdiff",
		call => \&getsetup);
	hook(type => "pagetemplate", id => "recentchangesdiff",
		call => \&pagetemplate);
	hook(type => "format", id => "recentchangesdiff.pm", call => \&format);
}

sub getsetup () {
	return 
		plugin => {
			safe => 1,
			rebuild => 1,
		},
}

sub pagetemplate (@) {
	my %params=@_;
	my $template=$params{template};
	if ($config{rcs} && exists $params{rev} && length $params{rev} &&
	    $template->query(name => "diff")) {
		my @lines=IkiWiki::rcs_diff($params{rev}, $maxlines+1);
		if (@lines) {
			my $diff;
			my $trunc=0;
			if (@lines > $maxlines) {
				$diff=join("", @lines[0..($maxlines-1)]);
				$trunc=1;
			}
			else {
				$diff=join("", @lines);
			}
			if (length $diff > 102400) {
				$diff=substr($diff, 0, 10240);
				$trunc=1;
			}
			if ($trunc) {
				$diff.="\n".gettext("(Diff truncated)");
			}
			# escape html
			$diff = encode_entities($diff);
			# escape links and preprocessor stuff
			$diff = encode_entities($diff, '\[\]');
			$template->param(diff => $diff);
		}
	}
}

sub format (@) {
        my %params=@_;

	if (! ($params{content}=~s!^(<body[^>]*>)!$1.include_javascript($params{page})!em)) {
		# no <body> tag, probably in preview mode
		$params{content}=include_javascript(undef).$params{content};
	}
	return $params{content};
}

# taken verbatim from toggle.pm
sub include_javascript ($) {
	my $from=shift;
	
	return '<script src="'.urlto("ikiwiki/ikiwiki.js", $from).
		'" type="text/javascript" charset="utf-8"></script>'."\n".
		'<script src="'.urlto("ikiwiki/toggle.js", $from).
		'" type="text/javascript" charset="utf-8"></script>';
}

1
