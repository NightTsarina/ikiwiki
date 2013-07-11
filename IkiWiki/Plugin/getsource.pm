#!/usr/bin/perl
package IkiWiki::Plugin::getsource;

use warnings;
use strict;
use IkiWiki;
use open qw{:utf8 :std};

sub import {
	hook(type => "getsetup", id => "getsource", call => \&getsetup);
	hook(type => "pagetemplate", id => "getsource", call => \&pagetemplate);
	hook(type => "cgi", id => "getsource", call => \&cgi_getsource);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 1,
			section => "web",
		},
		getsource_mimetype => {
			type => "string",
			example => "text/plain; charset=utf-8",
			description => "Mime type for returned source.",
			safe => 1,
			rebuild => 0,
		},
}

sub pagetemplate (@) {
	my %params=@_;

	my $page=$params{page};
	my $template=$params{template};

	if (length $config{cgiurl}) {
		$template->param(getsourceurl => IkiWiki::cgiurl(do => "getsource", page => $page));
		$template->param(have_actions => 1);
	}
}

sub cgi_getsource ($) {
	my $cgi=shift;

	return unless defined $cgi->param('do') &&
	              $cgi->param("do") eq "getsource";

	IkiWiki::decode_cgi_utf8($cgi);

	my $page=$cgi->param('page');

	if (! defined $page || $page !~ /$config{wiki_file_regexp}/) {
		error("invalid page parameter");
	}

	# For %pagesources.
	IkiWiki::loadindex();

	if (! exists $pagesources{$page}) {
		IkiWiki::cgi_custom_failure(
			$cgi,
			"404 Not Found",
			IkiWiki::cgitemplate($cgi, gettext("missing page"),
				"<p>".
				sprintf(gettext("The page %s does not exist."),
					htmllink("", "", $page)).
				"</p>"));
		exit;
	}

	if (! defined pagetype($pagesources{$page})) {
		IkiWiki::cgi_custom_failure(
			$cgi->header(-status => "403 Forbidden"),
			IkiWiki::cgitemplate($cgi, gettext("not a page"),
				"<p>".
				sprintf(gettext("%s is an attachment, not a page."),
					htmllink("", "", $page)).
				"</p>"));
		exit;
	}

	if (! $config{getsource_mimetype}) {
		$config{getsource_mimetype} = "text/plain; charset=utf-8";
	}

	print "Content-Type: $config{getsource_mimetype}\r\n";
	print ("\r\n");
	print readfile(srcfile($pagesources{$page}));

	exit 0;
}

1
