#!/usr/bin/perl
package IkiWiki::Plugin::mirrorlist;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "mirrorlist", call => \&getsetup);
	hook(type => "pagetemplate", id => "mirrorlist", call => \&pagetemplate);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 1,
			section => "web",
		},
		mirrorlist => {
			type => "string",
			example => {},
			description => "list of mirrors",
			safe => 1,
			rebuild => 1,
		},
		mirrorlist_use_cgi => {
			type => 'boolean',
			example => 1,
			description => "generate links that point to the mirrors' ikiwiki CGI",
			safe => 1,
			rebuild => 1,
		},
}

sub checkconfig () {
	if (! defined $config{mirrorlist_use_cgi}) {
		$config{mirrorlist_use_cgi}=0;
	}
}

sub pagetemplate (@) {
	my %params=@_;
        my $template=$params{template};
	
	if ($template->query(name => "extrafooter") &&
	    keys %{$config{mirrorlist}} > 0) {
		my $value=$template->param("extrafooter");
		$value.=mirrorlist($params{page});
		$template->param(extrafooter => $value);
	}
}

sub mirrorlist ($) {
	my $page=shift;
	return ($config{html5} ? '<nav id="mirrorlist">' : '<div>').
		(keys %{$config{mirrorlist}} > 1 ? gettext("Mirrors") : gettext("Mirror")).
		": ".
		join(", ",
			map { 
				qq{<a href="}.
				( $config{mirrorlist_use_cgi} ?
				  $config{mirrorlist}->{$_}."?do=goto&page=$page" :
				  $config{mirrorlist}->{$_}."/".urlto($page, "") ).
				qq{">$_</a>}
			} keys %{$config{mirrorlist}}
		).
		($config{html5} ? '</nav>' : '</div>');
}

1
