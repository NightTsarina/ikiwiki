#!/usr/bin/perl
package IkiWiki::Plugin::google;

use warnings;
use strict;
use IkiWiki 3.00;
use URI;

sub import {
	hook(type => "getsetup", id => "google", call => \&getsetup);
	hook(type => "checkconfig", id => "google", call => \&checkconfig);
	hook(type => "pagetemplate", id => "google", call => \&pagetemplate);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 1,
			section => "web",
		},
}

sub checkconfig () {
	if (! length $config{url}) {
		error(sprintf(gettext("Must specify %s when using the %s plugin"), "url", 'google'));
	}
	
	# This is a mass dependency, so if the search form template
	# changes, every page is rebuilt.
	add_depends("", "templates/googleform.tmpl");
}

my $form;
sub pagetemplate (@) {
	my %params=@_;
	my $page=$params{page};
	my $template=$params{template};

	# Add search box to page header.
	if ($template->query(name => "searchform")) {
		if (! defined $form) {
			my $searchform = template("googleform.tmpl", blind_cache => 1);
			$searchform->param(url => $config{url});
			$searchform->param(html5 => $config{html5});
			$form=$searchform->output;
		}

		$template->param(searchform => $form);
	}
}

1
