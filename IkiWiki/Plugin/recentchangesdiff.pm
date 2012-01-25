#!/usr/bin/perl
package IkiWiki::Plugin::recentchangesdiff;

use warnings;
use strict;
use IkiWiki 3.00;
use HTML::Entities;

my $maxlines=200;

sub import {
	hook(type => "getsetup", id => "recentchangesdiff",
		call => \&getsetup);
	hook(type => "pagetemplate", id => "recentchangesdiff",
		call => \&pagetemplate);
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

1
