#!/usr/bin/perl
# Ikiwiki password authentication.
package IkiWiki::Plugin::passwordauth;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "passwordauth", "call" => \&getsetup);
	hook(type => "formbuilder_setup", id => "passwordauth", call => \&formbuilder_setup);
	hook(type => "formbuilder", id => "passwordauth", call => \&formbuilder);
	hook(type => "sessioncgi", id => "passwordauth", call => \&sessioncgi);
	hook(type => "auth", id => "passwordauth", call => \&auth);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 0,
			section => "auth",
		},
		account_creation_password => {
			type => "string",
			example => "s3cr1t",
			description => "a password that must be entered when signing up for an account",
			safe => 1,
			rebuild => 0,
		},
		password_cost => {
			type => "integer",
			example => 8,
			description => "cost of generating a password using Authen::Passphrase::BlowfishCrypt",
			safe => 1,
			rebuild => 0,
		},
}

# Checks if a string matches a user's password, and returns true or false.
sub checkpassword ($$;$) {
	my $user=shift;
	my $password=shift;
	my $field=shift || "password";

	# It's very important that the user not be allowed to log in with
	# an empty password!
	if (! length $password) {
		return 0;
	}

	my $userinfo=IkiWiki::userinfo_retrieve();
	if (! length $user || ! defined $userinfo ||
	    ! exists $userinfo->{$user} || ! ref $userinfo->{$user}) {
		return 0;
	}

	my $ret=0;
	if (exists $userinfo->{$user}->{"crypt".$field}) {
		eval q{use Authen::Passphrase};
		error $@ if $@;
		my $p = Authen::Passphrase->from_crypt($userinfo->{$user}->{"crypt".$field});
		$ret=$p->match($password);
	}
	elsif (exists $userinfo->{$user}->{$field}) {
		$ret=$password eq $userinfo->{$user}->{$field};
	}

	if ($ret &&
	    (exists $userinfo->{$user}->{resettoken} ||
	     exists $userinfo->{$user}->{cryptresettoken})) {
		# Clear reset token since the user has successfully logged in.
		delete $userinfo->{$user}->{resettoken};
		delete $userinfo->{$user}->{cryptresettoken};
		IkiWiki::userinfo_store($userinfo);
	}

	return $ret;
}

sub setpassword ($$;$) {
	my $user=shift;
	my $password=shift;
	my $field=shift || "password";

	eval q{use Authen::Passphrase::BlowfishCrypt};
	if (! $@) {
		my $p = Authen::Passphrase::BlowfishCrypt->new(
			cost => $config{password_cost} || 8,
			salt_random => 1,
			passphrase => $password,
		);
		IkiWiki::userinfo_set($user, "crypt$field", $p->as_crypt);
		IkiWiki::userinfo_set($user, $field, "");
	}
	else {
		IkiWiki::userinfo_set($user, $field, $password);
	}

	# Setting the password clears any passwordless login token.
	if ($field ne 'passwordless') {
		IkiWiki::userinfo_set($user, "passwordless", "");
	}
}

# Generates a token that can be used to log the user in.
# This needs to be hard to guess. Generating a cgi session id will
# make it as hard to guess as any cgi session.
sub gentoken ($$;$) {
	my $user=shift;
	my $tokenfield=shift;
	my $reversable=shift;

	eval q{use CGI::Session};
	error($@) if $@;
	my $token = CGI::Session->new("driver:DB_File", undef, {FileName => "/dev/null"})->id;
	if (! $reversable) {
		setpassword($user, $token, $tokenfield);
	}
	else {
		IkiWiki::userinfo_set($user, $tokenfield, $token);
	}
	return $token;
}

# An anonymous user has no normal password, only a passwordless login
# token. Given an email address, this sets up such a user for that email,
# unless one already exists, and returns the username.
sub anonuser ($) {
	my $email=shift;

	# Want a username for this email that won't overlap with any other.
	my $user=$email;
	$user=~s/@/_/g;

	my $userinfo=IkiWiki::userinfo_retrieve();
	if (! exists $userinfo->{$user} || ! ref $userinfo->{$user}) {
		if (IkiWiki::userinfo_setall($user, {
		    	'email' => $email,
			'regdate' => time})) {
			gentoken($user, "passwordless", 1);
			return $user;
		}
		else {
			error(gettext("Error creating account."));
		}
	}
	elsif (defined anonusertoken($userinfo->{$user})) {
		return $user;
	}
	else {
		return undef;
	}
}

sub anonusertoken ($) {
	my $userhash=shift;
	if (exists $userhash->{passwordless} &&
	    length $userhash->{passwordless}) {
		return $userhash->{passwordless};
	}
	else {
		return undef;
	}
}

sub formbuilder_setup (@) {
	my %params=@_;

	my $form=$params{form};
	my $session=$params{session};
	my $cgi=$params{cgi};

	my $do_register=defined $cgi->param("do") && $cgi->param("do") eq "register";

	if ($form->title eq "signin" || $form->title eq "register" || $do_register) {
		$form->field(name => "name", required => 0);
		$form->field(name => "password", type => "password", required => 0);
		
		if ($form->submitted eq "Register" || $form->submitted eq "Create Account" || $do_register) {
			$form->field(name => "confirm_password", type => "password");
			$form->field(name => "account_creation_password", type => "password")
				 if (defined $config{account_creation_password} &&
				     length $config{account_creation_password});
			$form->field(name => "email", size => 50);
			$form->title("register");
			$form->text("");
		
			$form->field(name => "confirm_password",
				validate => sub {
					shift eq $form->field("password");
				},
			);
			$form->field(name => "password",
				validate => sub {
					shift eq $form->field("confirm_password");
				},
			);
		}

		if ($form->submitted) {
			my $submittype=$form->submitted;
			# Set required fields based on how form was submitted.
			my %required=(
				"Login" => [qw(name password)],
				"Register" => [],
				"Create Account" => [qw(name password confirm_password email)],
				"Reset Password" => [qw(name)],
			);
			foreach my $opt (@{$required{$submittype}}) {
				$form->field(name => $opt, required => 1);
			}
	
			if ($submittype eq "Create Account") {
				$form->field(
					name => "account_creation_password",
					validate => sub {
						shift eq $config{account_creation_password};
					},
					required => 1,
				) if (defined $config{account_creation_password} &&
				      length $config{account_creation_password});
				$form->field(
					name => "email",
					validate => "EMAIL",
				);
			}

			# Validate password against name for Login.
			if ($submittype eq "Login") {
				$form->field(
					name => "password",
					validate => sub {
						checkpassword(scalar $form->field("name"), shift);
					},
				);
			}
			elsif ($submittype eq "Register" ||
			       $submittype eq "Create Account" ||
			       $submittype eq "Reset Password") {
				$form->field(name => "password", validate => 'VALUE');
			}
			
			# And make sure the entered name exists when logging
			# in or sending email, and does not when registering.
			if ($submittype eq 'Create Account' ||
			    $submittype eq 'Register') {
				$form->field(
					name => "name",
					validate => sub {
						my $name=shift;
						length $name &&
						$name=~/$config{wiki_file_regexp}/ &&
						# don't allow registering
						# accounts that look like
						# openids, or email
						# addresses, even if the
						# file regexp allows it
						$name!~/[\/:\@]/ &&
						! IkiWiki::userinfo_get($name, "regdate");
					},
				);
			}
			elsif ($submittype eq "Login" ||
			       $submittype eq "Reset Password") {
				$form->field( 
					name => "name",
					validate => sub {
						my $name=shift;
						length $name &&
						IkiWiki::userinfo_get($name, "regdate");
					},
				);
			}
		}
		else {
			# First time settings.
			$form->field(name => "name");
			if ($session->param("name")) {
				$form->field(name => "name", value => $session->param("name"));
			}
		}
	}
	elsif ($form->title eq "preferences") {
		my $user=$session->param("name");
		if (! IkiWiki::openiduser($user) && ! IkiWiki::emailuser($user)) {
			$form->field(name => "name", disabled => 1, 
				value => $user, force => 1,
				fieldset => "login");
			$form->field(name => "password", type => "password",
				fieldset => "login",
				validate => sub {
					shift eq $form->field("confirm_password");
				});
			$form->field(name => "confirm_password", type => "password",
				fieldset => "login",
				validate => sub {
					shift eq $form->field("password");
				});
			
			my $userpage=IkiWiki::userpage($user);
			if (exists $pagesources{$userpage}) {
				$form->text(gettext("Your user page: ").
					htmllink("", "", $userpage,
						noimageinline => 1));
			}
			else {
				$form->text("<a rel=\"nofollow\" href=\"".
					IkiWiki::cgiurl(do => "edit", page => $userpage).
					"\">".gettext("Create your user page")."</a>");
			}
		}
	}
}

sub formbuilder (@) {
	my %params=@_;

	my $form=$params{form};
	my $session=$params{session};
	my $cgi=$params{cgi};
	my $buttons=$params{buttons};

	my $do_register=defined $cgi->param("do") && $cgi->param("do") eq "register";

	if ($form->title eq "signin" || $form->title eq "register") {
		if (($form->submitted && $form->validate) || $do_register) {
			my $user_name = $form->field('name');

			if ($form->submitted eq 'Login') {
				$session->param("name", $user_name);
				IkiWiki::cgi_postsignin($cgi, $session);
			}
			elsif ($form->submitted eq 'Create Account') {
				my $email = $form->field('email');
				my $password = $form->field('password');

				if (IkiWiki::userinfo_setall($user_name, {
					'email' => $email,
					'regdate' => time})) {
					setpassword($user_name, $password);
					$form->field(name => "confirm_password", type => "hidden");
					$form->field(name => "email", type => "hidden");
					$form->text(gettext("Account creation successful. Now you can Login."));
				}
				else {
					error(gettext("Error creating account."));
				}
			}
			elsif ($form->submitted eq 'Reset Password') {
				my $email=IkiWiki::userinfo_get($user_name, "email");
				if (! length $email) {
					error(gettext("No email address, so cannot email password reset instructions."));
				}

				my $token=gentoken($user_name, "resettoken");
				
				my $template=template("passwordmail.tmpl");
				$template->param(
					user_name => $user_name,
					passwordurl => IkiWiki::cgiurl_abs_samescheme(
						'do' => "reset",
						'name' => $user_name,
						'token' => $token,
					),
					wikiurl => $config{url},
					wikiname => $config{wikiname},
					remote_addr => $session->remote_addr(),
				);
				
				eval q{use Mail::Sendmail};
				error($@) if $@;
				sendmail(
					To => IkiWiki::userinfo_get($user_name, "email"),
					From => "$config{wikiname} admin <".
						(defined $config{adminemail} ? $config{adminemail} : "")
						.">",
					Subject => "$config{wikiname} information",
					Message => $template->output,
				) or error(gettext("Failed to send mail"));
				
				$form->text(gettext("You have been mailed password reset instructions."));
				$form->field(name => "name", required => 0);
				push @$buttons, "Reset Password";
			}
			elsif ($form->submitted eq "Register" || $do_register) {
				@$buttons="Create Account";
			}
		}
		elsif ($form->submitted eq "Create Account") {
			@$buttons="Create Account";
		}
		else {
			push @$buttons, "Register", "Reset Password";
		}
	}
	elsif ($form->title eq "preferences") {
		if ($form->submitted eq "Save Preferences" && $form->validate) {
			my $user_name=$form->field('name');
			my $password=$form->field('password');
			if (defined $password && length $password) {
				setpassword($user_name, $password);
			}
		}
	}
}

sub sessioncgi ($$) {
	my $q=shift;
	my $session=shift;

	if ($q->param('do') eq 'reset') {
		my $name=$q->param("name");
		my $token=$q->param("token");

		if (! defined $name || ! defined $token ||
		    ! length $name  || ! length $token) {
			error(gettext("incorrect password reset url"));
	 	}
		if (! checkpassword($name, $token, "resettoken")) {
			error(gettext("password reset denied"));
		}

		$session->param("name", $name);
		IkiWiki::cgi_prefs($q, $session);
		exit;
	}
	elsif ($q->param('do') eq 'tokenauth') {
		my $name=$q->param("name");
		my $token=$q->param("token");

		if (! defined $name || ! defined $token ||
		    ! length $name  || ! length $token) {
			error(gettext("incorrect url"));
	 	}
		if (! checkpassword($name, $token, "passwordless")) {
			error(gettext("access denied"));
		}

		$session->param("name", $name);
		IkiWiki::cgi_prefs($q, $session);
		exit;
	}
	elsif ($q->param("do") eq "register") {
		# After registration, need to go somewhere, so show prefs page.
		$session->param(postsignin => "do=prefs");
		# Due to do=register, this will run in registration-only
		# mode.
		IkiWiki::cgi_signin($q, $session);
		exit;
	}
}

sub auth ($$) {
	# While this hook is not currently used, it needs to exist
	# so ikiwiki knows that the wiki supports logins, and will
	# enable the Preferences page.
}

1
