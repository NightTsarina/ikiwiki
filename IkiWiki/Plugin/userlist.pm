#!/usr/bin/perl
package IkiWiki::Plugin::userlist;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "userlist", call => \&getsetup);
	hook(type => "sessioncgi", id => "userlist", call => \&sessioncgi);
	hook(type => "formbuilder_setup", id => "userlist",
		call => \&formbuilder_setup);
}

sub getsetup () {
        return
		plugin => {
			safe => 1,
			rebuild => 0,
			section => "web",
		},
}

sub sessioncgi ($$) {
	my $cgi=shift;
	my $session=shift;

	if ($cgi->param("do") eq "userlist") {
		showuserlist($cgi, $session);
		exit;
	}
}

sub formbuilder_setup (@) {
	my %params=@_;

	my $form=$params{form};
	if ($form->title eq "preferences" &&
	    IkiWiki::is_admin($params{session}->param("name"))) {
		push @{$params{buttons}}, "Users";
		if ($form->submitted && $form->submitted eq "Users") {
			showuserlist($params{cgi}, $params{session});
			exit;
		}
	}
}

sub showuserlist ($$) {
	my $q=shift;
	my $session=shift;

	IkiWiki::needsignin($q, $session);
	if (! defined $session->param("name") ||
	    ! IkiWiki::is_admin($session->param("name"))) {
		error(gettext("you are not logged in as an admin"));
	}

	my $h="<table border=\"1\">\n";
	$h.="<tr><th>".gettext("login")."</th><th>".gettext("email")."</th></tr>\n";
	my $info=IkiWiki::userinfo_retrieve();
	eval q{use HTML::Entities};
	if (ref $info) {
		foreach my $user (sort { $info->{$a}->{regdate} <=> $info->{$b}->{regdate} } keys %$info) {
			my %i=%{$info->{$user}};
			$h.="<tr><td>".encode_entities($user)."</td><td>".
				encode_entities(defined $i{email} ? $i{email} : "").
				"</td></tr>\n";
		}
	}
	$h.="</table>\n";

	IkiWiki::printheader($session);
	print IkiWiki::cgitemplate(undef, gettext("Users"), $h);
}

1
