#!/usr/bin/perl
package IkiWiki::Plugin::link;

use warnings;
use strict;
use IkiWiki 3.00;

my $link_regexp;

my $email_regexp = qr/^(?:[a-z0-9!#$%&'*+\/=?^_`{|}~-]+(?:\.[a-z0-9!#$%&'*+\/=?^_`{|}~-]+)*|"(?:[\x01-\x08\x0b\x0c\x0e-\x1f\x21\x23-\x5b\x5d-\x7f]|\\[\x01-\x09\x0b\x0c\x0e-\x7f])*")@(?:(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]*[a-z0-9])?|\[(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?|[a-z0-9-]*[a-z0-9]:(?:[\x01-\x08\x0b\x0c\x0e-\x1f\x21-\x5a\x53-\x7f]|\\[\x01-\x09\x0b\x0c\x0e-\x7f])+)\])$/i; 
my $url_regexp = qr/^(?:[^:]+:\/\/|mailto:).*/i;

sub import {
	hook(type => "getsetup", id => "link", call => \&getsetup);
	hook(type => "checkconfig", id => "link", call => \&checkconfig);
	hook(type => "linkify", id => "link", call => \&linkify);
	hook(type => "scan", id => "link", call => \&scan);
	hook(type => "renamepage", id => "link", call => \&renamepage);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 1,
			section => "core",
		},
}

sub checkconfig () {
	if ($config{prefix_directives}) {
		$link_regexp = qr{
			\[\[(?=[^!])            # beginning of link
			(?:
				([^\]\|]+)      # 1: link text
				\|              # followed by '|'
			)?                      # optional
			
			([^\n\r\]#]+)           # 2: page to link to
			(?:
				\#              # '#', beginning of anchor
				([^\s\]]+)      # 3: anchor text
			)?                      # optional
			
			\]\]                    # end of link
		}x;
	}
	else {
		$link_regexp = qr{
			\[\[                    # beginning of link
			(?:
				([^\]\|\n\s]+)  # 1: link text
				\|              # followed by '|'
			)?                      # optional

			([^\s\]#]+)             # 2: page to link to
			(?:
				\#              # '#', beginning of anchor
				([^\s\]]+)      # 3: anchor text
			)?                      # optional

			\]\]                    # end of link
		}x;
	}
}

sub is_externallink ($$) {
	my $page = shift;
	my $url = shift;
	if ($url =~ /$email_regexp/) {
		# url looks like an email address, so we assume it
		# is supposed to be an external link if there is no
		# page with that name.
		$url =~ s/#.*//;
		return (! (bestlink($page, linkpage($url))))
	}
	return ($url =~ /$url_regexp/)
}

sub externallink ($;@) {
	my $url = shift;
	my $pagetitle = shift;

	# build pagetitle
	if (!($pagetitle)) {
		$pagetitle = $url;
		# use only the email address as title for mailto: urls
		if ($pagetitle =~ /^mailto:.*/) {
			$pagetitle =~ s/^mailto:([^?]+).*/$1/;
		}
	}

	# handle email-addresses (without mailto:):
	if ($url =~ /$email_regexp/) {
		$url = "mailto:" . $url;
	}

	return "<a href=\"$url\">$pagetitle</a>";
}

sub linkify (@) {
	my %params=@_;
	my $page=$params{page};
	my $destpage=$params{destpage};

	$params{content} =~ s{(\\?)$link_regexp}{
		defined $2
			? ( $1 
				? "[[$2|$3".($4 ? "#$4" : "")."]]" 
				: is_externallink($page, $3 . ($4 ? "#$4" : ""))
					? externallink("$3" . ($4 ? "#$4" : ""), $2)
					: htmllink($page, $destpage, linkpage($3),
						anchor => $4, linktext => pagetitle($2)))
			: ( $1 
				? "[[$3".($4 ? "#$4" : "")."]]"
				: is_externallink($page, $3 . ($4 ? "#$4" : ""))
					? externallink("$3" . ($4 ? "#$4" : ""))
					: htmllink($page, $destpage, linkpage($3),
						anchor => $4))
	}eg;
	
	return $params{content};
}

sub scan (@) {
	my %params=@_;
	my $page=$params{page};
	my $content=$params{content};

	while ($content =~ /(?<!\\)$link_regexp/g) {
		if (! is_externallink($page, $2 . ($3 ? "#$3" : ""))) {
			add_link($page, linkpage($2));
		}
	}
}

sub renamepage (@) {
	my %params=@_;
	my $page=$params{page};
	my $old=$params{oldpage};
	my $new=$params{newpage};

	$params{content} =~ s{(?<!\\)$link_regexp}{
		if (! is_externallink($page, $2 . ($3 ? "#$3" : ""))) {
			my $linktext=$2;
			my $link=$linktext;
			if (bestlink($page, linkpage($linktext)) eq $old) {
				$link=pagetitle($new, 1);
				$link=~s/ /_/g;
				if ($linktext =~ m/.*\/*?[A-Z]/) {
					# preserve leading cap of last component
					my @bits=split("/", $link);
					$link=join("/", @bits[0..$#bits-1], ucfirst($bits[$#bits]));
				}
				if (index($linktext, "/") == 0) {
					# absolute link
					$link="/$link";
				}
			}
			defined $1
				? ( "[[$1|$link".($3 ? "#$3" : "")."]]" )
				: ( "[[$link".   ($3 ? "#$3" : "")."]]" )
		}
	}eg;

	return $params{content};
}

1
