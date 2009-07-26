#!/usr/bin/perl
package IkiWiki::Plugin::getsource;

use warnings;
use strict;
use IkiWiki;
use open qw{:utf8 :std};

sub import {
	hook(type => "getsetup", id => "getsource", call => \&getsetup);
	hook(type => "pagetemplate", id => "getsource", call => \&pagetemplate);
	hook(type => "sessioncgi", id => "getsource", call => \&cgi_getsource);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 1,
		},
		getsource_mimetype => {
			type => "string",
			example => "application/octet-stream",
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

sub cgi_getsource ($$) {
	my $cgi=shift;
	my $session=shift;

	# Note: we use sessioncgi rather than just cgi
	# because we need $IkiWiki::pagesources{} to be
	# populated.

	return unless (defined $cgi->param('do') &&
					$cgi->param("do") eq "getsource");

	IkiWiki::decode_cgi_utf8($cgi);

	my $page=$cgi->param('page');

	if ($IkiWiki::pagesources{$page}) {
		
		my $data = IkiWiki::readfile(IkiWiki::srcfile($IkiWiki::pagesources{$page}));
		
		if (! $config{getsource_mimetype}) {
			$config{getsource_mimetype} = "text/plain";
		}
		
		print "Content-Type: $config{getsource_mimetype}\r\n";
		
		print ("\r\n");
		
		print $data;
		
		exit 0;
	}
	
	error("Unable to find page source for page: $page");

	exit 0;
}

1
