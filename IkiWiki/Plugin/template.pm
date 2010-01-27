#!/usr/bin/perl
# Structured template plugin.
package IkiWiki::Plugin::template;

use warnings;
use strict;
use IkiWiki 3.00;
use HTML::Template;
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

	my $template_page="templates/$params{id}";
	add_depends($params{page}, $template_page);

	my $template_file=$pagesources{$template_page};
	return sprintf(gettext("template %s not found"),
		htmllink($params{page}, $params{destpage}, "/".$template_page))
			unless defined $template_file;

	my $template;
	eval {
		$template=HTML::Template->new(
	        	filter => sub {
	                        my $text_ref = shift;
	                        $$text_ref=&Encode::decode_utf8($$text_ref);
				chomp $$text_ref;
	                },
	                filename => srcfile($template_file),
       			die_on_bad_params => 0,
			no_includes => 1,
			blind_cache => 1,
		);
	};
	if ($@) {
		error gettext("failed to process:")." $@"
	}

	$params{basename}=IkiWiki::basename($params{page});

	foreach my $param (keys %params) {
		my $value=IkiWiki::preprocess($params{page}, $params{destpage},
		          IkiWiki::filter($params{page}, $params{destpagea},
		          $params{$param}), $scan);
		if ($template->query(name => $param)) {
			$template->param($param =>
				IkiWiki::htmlize($params{page}, $params{destpage},
					pagetype($pagesources{$params{page}}),
					$value));
		}
		if ($template->query(name => "raw_$param")) {
			$template->param("raw_$param" => $value);
		}
	}

	return IkiWiki::preprocess($params{page}, $params{destpage},
	       IkiWiki::filter($params{page}, $params{destpage},
	       $template->output), $scan);
}

1
