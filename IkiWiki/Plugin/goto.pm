#!/usr/bin/perl
package IkiWiki::Plugin::goto;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "cgi", id => 'goto',  call => \&cgi);
	hook(type => "getsetup", id => 'goto',  call => \&getsetup);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 0,
			section => "web",
		}
}

# cgi_goto(CGI, [page])
# Redirect to a specified page, or display "not found". If not specified,
# the page param from the CGI object is used.
sub cgi_goto ($;$) {
	my $q = shift;
	my $page = shift;

	if (!defined $page) {
		$page = IkiWiki::decode_utf8(scalar $q->param("page"));

		if (!defined $page) {
			error("missing page parameter");
		}
	}

	# It's possible that $page is not a valid page name;
	# if so attempt to turn it into one.
	if ($page !~ /$config{wiki_file_regexp}/) {
		$page=titlepage($page);
	}

	IkiWiki::loadindex();

	my $link;
	if (! IkiWiki::isinternal($page)) {
		$link = bestlink("", $page);
	}
	elsif (defined $pagestate{$page}{meta}{permalink}) {
		# Can only redirect to an internal page if it has a
		# permalink.
		IkiWiki::redirect($q, $pagestate{$page}{meta}{permalink});
	}

	if (! defined $link || ! length $link) {
		IkiWiki::cgi_custom_failure(
			$q,
			"404 Not Found",
			IkiWiki::cgitemplate($q, gettext("missing page"),
				"<p>".
				sprintf(gettext("The page %s does not exist."),
					htmllink("", "", $page)).
				"</p>")
		)
	}
	else {
		IkiWiki::redirect($q, urlto($link));
	}

	exit;
}

sub cgi ($) {
	my $cgi=shift;
	my $do = $cgi->param('do');

	if (defined $do && ($do eq 'goto' || $do eq 'commenter' ||
	                       $do eq 'recentchanges_link')) {
		# goto is the preferred name for this; recentchanges_link and
		# commenter are for compatibility with any saved URLs
		cgi_goto($cgi);
	}
}

1;
