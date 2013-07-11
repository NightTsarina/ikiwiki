#!/usr/bin/perl
package IkiWiki::Receive;

use warnings;
use strict;
use IkiWiki;

sub getuser () {
	my $user=(getpwuid(exists $ENV{CALLER_UID} ? $ENV{CALLER_UID} : $<))[0];
	if (! defined $user) {
		error("cannot determine username for $<");
	}
	return $user;
}

sub trusted () {
	my $user=getuser();
	return ! ref $config{untrusted_committers} ||
		! grep { $_ eq $user } @{$config{untrusted_committers}};
}

sub genwrapper () {
	# Test for commits from untrusted committers in the wrapper, to
	# avoid starting ikiwiki proper at all for trusted commits.

	my $ret=<<"EOF";
	{
		int u=getuid();
EOF
	$ret.="\t\tif ( ".
		join("&&", map {
			my $uid=getpwnam($_);
			if (! defined $uid) {
				error(sprintf(gettext("cannot determine id of untrusted committer %s"), $_));
			}
			"u != $uid";
		} @{$config{untrusted_committers}}).
		") {\n";

	
	$ret.=<<"EOF";
			/* Trusted user.
			 * Consume all stdin before exiting, as git may
			 * otherwise be unhappy. */
			char buf[256];
			while (read(0, &buf, 256) != 0) {}
			exit(0);
		}
		asprintf(&s, "CALLER_UID=%i", u);
		newenviron[i++]=s;
	}
EOF
	return $ret;
}

sub test () {
	exit 0 if trusted();

	IkiWiki::lockwiki();
	IkiWiki::loadindex();

	# Dummy up a cgi environment to use when calling check_canedit
	# and friends.
	eval q{use CGI};
	error($@) if $@;
	my $cgi=CGI->new;

	# And dummy up a session object.
	require IkiWiki::CGI;
	my $session=IkiWiki::cgi_getsession($cgi);
	$session->param("name", getuser());
	# Make sure whatever user was authed is in the
	# userinfo db.
	require IkiWiki::UserInfo;
	if (! IkiWiki::userinfo_get($session->param("name"), "regdate")) {
		IkiWiki::userinfo_setall($session->param("name"), {
			email => "",
			password => "",
			regdate => time,
		}) || error("failed adding user");
	}

	IkiWiki::check_canchange(
		cgi => $cgi,
		session => $session,
		changes => [IkiWiki::rcs_receive()]
	);
	exit 0;
}

1
