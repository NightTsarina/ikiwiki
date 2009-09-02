#!/usr/bin/perl
# Ikiwiki unixauth authentication.
package IkiWiki::Plugin::unixauth;

use warnings;
use strict;
use IkiWiki 2.00;

sub import {
	hook(type => "getsetup", id => "unixauth", call => \&getsetup);
		hook(type => "formbuilder_setup", id => "unixauth",
			call => \&formbuilder_setup);
		hook(type => "formbuilder", id => "unixauth",
			call => \&formbuilder);
	hook(type => "sessioncgi", id => "unixauth", call => \&sessioncgi);
}

sub getsetup () {
	return
	unixauth_type => {
			type => "string",
			example => "checkpassword",
			description => "type of authenticator; can be 'checkpassword' or 'pwauth'",
			safe => 0,
			rebuild => 1,
	},
	unixauth_command => {
			type => "string",
			example => "/path/to/checkpassword",
			description => "full path and any arguments",
			safe => 0,
			rebuild => 1,
	},
	unixauth_requiressl => {
			type => "boolean",
			example => "1",
			description => "require SSL? strongly recommended",
			safe => 0,
			rebuild => 1,
	},
	plugin => {
			description => "Unix user authentication",
			safe => 0,
			rebuild => 1,
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

	my $ret=0;
	if (! exists $config{unixauth_type}) {
			# admin needs to carefully think over his configuration
			return 0;
	}
	elsif ($config{unixauth_type} eq "checkpassword") {
			open UNIXAUTH, "|$config{unixauth_command} true 3<&0" or die("Could not run $config{unixauth_type}");
			print UNIXAUTH "$user\0$password\0Y123456\0";
			close UNIXAUTH;
			$ret=!($?>>8);
	}
	elsif ($config{unixauth_type} eq "pwauth") {
			open UNIXAUTH, "|$config{unixauth_command}" or die("Could not run $config{unixauth_type}");
			print UNIXAUTH "$user\n$password\n";
			close UNIXAUTH;
			$ret=!($?>>8);
	}
	else {
			# no such authentication type
			return 0;
	}

	if ($ret) {
		my $userinfo=IkiWiki::userinfo_retrieve();
		if (! length $user || ! defined $userinfo ||
			! exists $userinfo->{$user} || ! ref $userinfo->{$user}) {
				IkiWiki::userinfo_setall($user, {
					'email' => '',
					'regdate' => time,
				});
		}
	}

	return $ret;
}

sub formbuilder_setup (@) {
	my %params=@_;

	my $form=$params{form};
	my $session=$params{session};
	my $cgi=$params{cgi};

	# if not under SSL, die before even showing a login form,
	# unless the admin explicitly says it's fine
	if (! exists $config{unixauth_requiressl}) {
			$config{unixauth_requiressl} = 1;
	}
	if ($config{unixauth_requiressl}) {
		if ((! $config{sslcookie}) || (! exists $ENV{'HTTPS'})) {
			die("SSL required to login. Contact your administrator.<br>");
		}
	}

	if ($form->title eq "signin") {
			$form->field(name => "name", required => 0);
			$form->field(name => "password", type => "password", required => 0);

			if ($form->submitted) {
					my $submittype=$form->submitted;
					# Set required fields based on how form was submitted.
					my %required=(
							"Login" => [qw(name password)],
					);
					foreach my $opt (@{$required{$submittype}}) {
							$form->field(name => $opt, required => 1);
					}

					# Validate password against name for Login.
					if ($submittype eq "Login") {
							$form->field(
									name => "password",
									validate => sub {
											checkpassword($form->field("name"), shift);
									},
							);
					}

					# XXX is this reachable? looks like no
					elsif ($submittype eq "Login") {
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
		$form->field(name => "name", disabled => 1,
				value => $session->param("name"), force => 1,
				fieldset => "login");
		$form->field(name => "password", disabled => 1, type => "password",
				fieldset => "login"),
	}
}

sub formbuilder (@) {
	my %params=@_;

	my $form=$params{form};
	my $session=$params{session};
	my $cgi=$params{cgi};
	my $buttons=$params{buttons};

	if ($form->title eq "signin") {
		if ($form->submitted && $form->validate) {
			if ($form->submitted eq 'Login') {
				$session->param("name", $form->field("name"));
				IkiWiki::cgi_postsignin($cgi, $session);
			}
		}
	}
	elsif ($form->title eq "preferences") {
		if ($form->submitted eq "Save Preferences" && $form->validate) {
			my $user_name=$form->field('name');
		}
	}
}

sub sessioncgi ($$) {
	my $q=shift;
	my $session=shift;
}

1
