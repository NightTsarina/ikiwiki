#!/usr/bin/perl
package IkiWiki::Plugin::theme;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "theme", call => \&getsetup);
	hook(type => "checkconfig", id => "theme", call => \&checkconfig);
	hook(type => "needsbuild", id => "theme", call => \&needsbuild);
	hook(type => "pagetemplate", id => "theme", call => \&pagetemplate);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 0,
			section => "web",
		},
		theme => {
			type => "string",
			example => "actiontabs",
			description => "name of theme to enable",
			safe => 1,
			rebuild => 0,
		},
}

my $added=0;
sub checkconfig () {
	if (! $added && exists $config{theme} && $config{theme} =~ /^\w+$/) {
		add_underlay("themes/".$config{theme});
		$added=1;
	}
}

sub needsbuild ($) {
	my $needsbuild=shift;
	if (($config{theme} || '') ne ($wikistate{theme}{currenttheme} || '')) {
		# theme changed; ensure all files in the theme are built
		my %needsbuild=map { $_ => 1 } @$needsbuild;
		if ($config{theme}) {
			foreach my $file (glob("$config{underlaydirbase}/themes/$config{theme}/*")) {
				if (-f $file) {
					my $f=IkiWiki::basename($file);
					push @$needsbuild, $f
						unless $needsbuild{$f};
				}
			}
		}
		elsif ($wikistate{theme}{currenttheme}) {
			foreach my $file (glob("$config{underlaydirbase}/themes/$wikistate{theme}{currenttheme}/*")) {
				my $f=IkiWiki::basename($file);
				if (-f $file && defined eval { srcfile($f) }) {
					push @$needsbuild, $f;
				}
			}
		}
		
		$wikistate{theme}{currenttheme}=$config{theme};
	}
	return $needsbuild;
}

sub pagetemplate (@) {
	my %params=@_;
	my $template=$params{template};
	if (exists $config{theme} && length $config{theme})  {
		$template->param("theme_$config{theme}" => 1);
	}
}

1
