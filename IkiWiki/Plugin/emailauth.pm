#!/usr/bin/perl
# Ikiwiki email address as login
package IkiWiki::Plugin::emailauth;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "emailauth", "call" => \&getsetup);
	hook(type => "cgi", id => "cgi", "call" => \&cgi);
	IkiWiki::loadplugin("loginselector");
	IkiWiki::Plugin::loginselector::register_login_plugin(
		"emailauth",
		\&email_setup,
		\&email_check_input,
		\&email_auth,
	);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 0,
			section => "auth",
		},
}

sub email_setup ($$) {
	my $q=shift;
	my $template=shift;

	return 1;
}

sub email_check_input ($) {
	my $cgi=shift;
	defined $cgi->param('do')
		&& $cgi->param("do") eq "signin"
		&& defined $cgi->param('Email_entry')
		&& length $cgi->param('Email_entry');
}

# Send login link to email.
sub email_auth ($$$$) {
	my $cgi=shift;
	my $session=shift;
	my $errordisplayer=shift;
	my $infodisplayer=shift;

	my $email=$cgi->param('Email_entry');
	unless ($email =~ /.\@./) {
		$errordisplayer->(gettext("Invalid email address."));
		return;
	}

	# Implicit account creation.
	my $userinfo=IkiWiki::userinfo_retrieve();
	if (! exists $userinfo->{$email} || ! ref $userinfo->{$email}) {
		IkiWiki::userinfo_setall($email, {
			'email' => $email,
			'regdate' => time,
		});
	}

	my $token=gentoken($email, $session);
	my $template=template("emailauth.tmpl");
	$template->param(
		wikiname => $config{wikiname},
		# Intentionally using short field names to keep link short.
		authurl => IkiWiki::cgiurl_abs(
			'e' => $email,
			'v' => $token,
		),
	);
	
	eval q{use Mail::Sendmail};
	error($@) if $@;
	sendmail(
		To => $email,
		From => "$config{wikiname} admin <".
			(defined $config{adminemail} ? $config{adminemail} : "")
			.">",
		Subject => "$config{wikiname} login",
		Message => $template->output,
	) or error(gettext("Failed to send mail"));

	$infodisplayer->(gettext("You have been sent an email, with a link you can open to complete the login process."));
}

# Finish login process.
sub cgi ($$) {
	my $cgi=shift;

	my $email=$cgi->param('e');
	my $v=$cgi->param('v');
	if (defined $email && defined $v && length $email && length $v) {
		my $token=gettoken($email);
		if ($token eq $v) {
			cleartoken($email);
			my $session=getsession($email);
			IkiWiki::cgi_postsignin($cgi, $session);
		}
		elsif (length $token ne length $cgi->param('v')) {
			error(gettext("Wrong login token length. Please check that you pasted in the complete login link from the email!"));
		}
		else {
			loginfailure();
		}
	}
}

# Generates the token that will be used in the authurl to log the user in.
# This needs to be hard to guess, and relatively short. Generating a cgi
# session id will make it as hard to guess as any cgi session.
#
# Store token in userinfo; this allows the user to log in
# using a different browser session, if it takes a while for the
# email to get to them.
#
# The postsignin value from the session is also stored in the userinfo
# to allow resuming in a different browser session.
sub gentoken ($$) {
	my $email=shift;
	my $session=shift;
	eval q{use CGI::Session};
	error($@) if $@;
	my $token = CGI::Session->new->id;
	IkiWiki::userinfo_set($email, "emailauthexpire", time+(60*60*24));
	IkiWiki::userinfo_set($email, "emailauth", $token);
	IkiWiki::userinfo_set($email, "emailauthpostsignin", defined $session->param("postsignin") ? $session->param("postsignin") : "");
	return $token;
}

# Gets the token, checking for expiry.
sub gettoken ($) {
	my $email=shift;
	my $val=IkiWiki::userinfo_get($email, "emailauth");
	my $expire=IkiWiki::userinfo_get($email, "emailauthexpire");
	if (! length $val || time > $expire) {
		loginfailure();
	}
	return $val;
}

# Generate a session to use after successful login.
sub getsession ($) {
	my $email=shift;

	IkiWiki::lockwiki();
	IkiWiki::loadindex();
	my $session=IkiWiki::cgi_getsession();

	my $postsignin=IkiWiki::userinfo_get($email, "emailauthpostsignin");
	IkiWiki::userinfo_set($email, "emailauthpostsignin", "");
	if (defined $postsignin && length $postsignin) {
		$session->param(postsignin => $postsignin);
	}

	$session->param(name => $email);
	my $nickname=$email;
	$nickname=~s/@.*//;
	$session->param(nickname => Encode::decode_utf8($nickname));

	IkiWiki::cgi_savesession($session);

	return $session;
}

sub cleartoken ($) {
	my $email=shift;
	IkiWiki::userinfo_set($email, "emailauthexpire", 0);
	IkiWiki::userinfo_set($email, "emailauth", "");
}

sub loginfailure () {
	error "Bad email authentication token. Please retry login.";
}

1
