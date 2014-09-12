#!/usr/bin/perl
# Structured template plugin.
package IkiWiki::Plugin::template;

use warnings;
use strict;
use IkiWiki 3.00;
use Encode;

sub import {
	hook(type => "getsetup", id => "template", call => \&getsetup);
	hook(type => "preprocess", id => "template", call => \&preprocess,
		scan => 1);
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

	# This needs to run even in scan mode, in order to process
	# links and other metadata included via the template.
	my $scan=! defined wantarray;

	if (! exists $params{id}) {
		error gettext("missing id parameter")
	}

	# The bare id is used, so a page templates/$id can be used as 
	# the template.
	my $template;
	eval {
		$template=template_depends($params{id}, $params{page},
			blind_cache => 1);
	};
	if ($@) {
		# gettext can clobber $@
		my $error = $@;
		error sprintf(gettext("failed to process template %s"),
			htmllink($params{page}, $params{destpage},
				"/templates/$params{id}"))." $error";
	}

	$params{basename}=IkiWiki::basename($params{page});

	foreach my $param (keys %params) {
		my $value=IkiWiki::preprocess($params{page}, $params{destpage},
		          $params{$param}, $scan);
		if ($template->query(name => $param)) {
			my $htmlvalue=IkiWiki::htmlize($params{page}, $params{destpage},
					pagetype($pagesources{$params{page}}),
					$value);
			chomp $htmlvalue;
			$template->param($param => $htmlvalue);
		}
		if ($template->query(name => "raw_$param")) {
			chomp $value;
			$template->param("raw_$param" => $value);
		}
	}

	return IkiWiki::preprocess($params{page}, $params{destpage},
	       $template->output, $scan);
}

1
