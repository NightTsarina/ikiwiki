#!/usr/bin/perl
# OpenID support.
package IkiWiki::Plugin::openid;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getopt", id => "openid", call => \&getopt);
	hook(type => "getsetup", id => "openid", call => \&getsetup);
	hook(type => "auth", id => "openid", call => \&auth);
	hook(type => "formbuilder_setup", id => "openid",
		call => \&formbuilder_setup, last => 1);
}

sub getopt () {
	eval q{use Getopt::Long};
	error($@) if $@;
	Getopt::Long::Configure('pass_through');
	GetOptions("openidsignup=s" => \$config{openidsignup});
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 0,
			section => "auth",
		},
		openidsignup => {
			type => "string",
			example => "http://myopenid.com/",
			description => "an url where users can signup for an OpenID",
			safe => 1,
			rebuild => 0,
		},
}

sub formbuilder_setup (@) {
	my %params=@_;

	my $form=$params{form};
	my $session=$params{session};
	my $cgi=$params{cgi};
	
	if ($form->title eq "signin") {
		# Give up if module is unavailable to avoid
		# needing to depend on it.
		eval q{use Net::OpenID::Consumer};
		if ($@) {
			debug("unable to load Net::OpenID::Consumer, not enabling OpenID login ($@)");
			return;
		}

		# This avoids it displaying a redundant label for the
		# OpenID fieldset.
		$form->fieldsets("OpenID");

		$form->field(
			name => "openid_url",
			label => gettext("Log in with")." ".htmllink("", "", "ikiwiki/OpenID", noimageinline => 1),
			fieldset => "OpenID",
			size => 30,
			comment => ($config{openidsignup} ? " | <a href=\"$config{openidsignup}\">".gettext("Get an OpenID")."</a>" : "")
		);

		# Handle submission of an OpenID as validation.
		if ($form->submitted && $form->submitted eq "Login" &&
		    defined $form->field("openid_url") && 
		    length $form->field("openid_url")) {
			$form->field(
				name => "openid_url",
				validate => sub {
					validate($cgi, $session, shift, $form);
				},
			);
			# Skip all other required fields in this case.
			foreach my $field ($form->field) {
				next if $field eq "openid_url";
				$form->field(name => $field, required => 0,
					validate => '/.*/');
			}
		}
	}
	elsif ($form->title eq "preferences" &&
	       IkiWiki::openiduser($session->param("name"))) {
		$form->field(name => "openid_url", disabled => 1,
			label => htmllink("", "", "ikiwiki/OpenID", noimageinline => 1),
			value => $session->param("name"), 
			size => 50, force => 1,
			fieldset => "login");
		$form->field(name => "email", type => "hidden");
	}
}

sub validate ($$$;$) {
	my $q=shift;
	my $session=shift;
	my $openid_url=shift;
	my $form=shift;

	my $csr=getobj($q, $session);

	my $claimed_identity = $csr->claimed_identity($openid_url);
	if (! $claimed_identity) {
		if ($form) {
			# Put the error in the form and fail validation.
			$form->field(name => "openid_url", comment => $csr->err);
			return 0;
		}
		else {
			error($csr->err);
		}
	}

	# Ask for client to provide a name and email, if possible.
	# Try sreg and ax
	if ($claimed_identity->can("set_extension_args")) {
		$claimed_identity->set_extension_args(
			'http://openid.net/extensions/sreg/1.1',
			{
				optional => 'email,fullname,nickname',
			},
		);
		$claimed_identity->set_extension_args(
			'http://openid.net/srv/ax/1.0',
			{
				mode => 'fetch_request',
				'required' => 'email,fullname,nickname,firstname',
				'type.email' => "http://schema.openid.net/contact/email",
				'type.fullname' => "http://axschema.org/namePerson",
				'type.nickname' => "http://axschema.org/namePerson/friendly",
				'type.firstname' => "http://axschema.org/namePerson/first",
			},
		);
	}

	my $check_url = $claimed_identity->check_url(
		return_to => IkiWiki::cgiurl(do => "postsignin"),
		trust_root => $config{cgiurl},
		delayed_return => 1,
	);
	# Redirect the user to the OpenID server, which will
	# eventually bounce them back to auth()
	IkiWiki::redirect($q, $check_url);
	exit 0;
}

sub auth ($$) {
	my $q=shift;
	my $session=shift;

	if (defined $q->param('openid.mode')) {
		my $csr=getobj($q, $session);

		if (my $setup_url = $csr->user_setup_url) {
			IkiWiki::redirect($q, $setup_url);
		}
		elsif ($csr->user_cancel) {
			IkiWiki::redirect($q, $config{url});
		}
		elsif (my $vident = $csr->verified_identity) {
			$session->param(name => $vident->url);

			my @extensions;
			if ($vident->can("signed_extension_fields")) {
				@extensions=grep { defined } (
					$vident->signed_extension_fields('http://openid.net/extensions/sreg/1.1'),
					$vident->signed_extension_fields('http://openid.net/srv/ax/1.0'),
				);
			}
			foreach my $ext (@extensions) {
				foreach my $field (qw{value.email email}) {
					if (exists $ext->{$field} &&
					    defined $ext->{$field} &&
					    length $ext->{$field}) {
						$session->param(email => $ext->{$field});
						last;
					}
				}
				foreach my $field (qw{value.nickname nickname value.fullname fullname value.firstname}) {
					if (exists $ext->{$field} &&
					    defined $ext->{$field} &&
					    length $ext->{$field}) {
						$session->param(username => $ext->{$field});
						last;
					}
				}
			}
		}
		else {
			error("OpenID failure: ".$csr->err);
		}
	}
	elsif (defined $q->param('openid_identifier')) {
		# myopenid.com affiliate support
		validate($q, $session, $q->param('openid_identifier'));
	}
}

sub getobj ($$) {
	my $q=shift;
	my $session=shift;

	eval q{use Net::OpenID::Consumer};
	error($@) if $@;

	my $ua;
	eval q{use LWPx::ParanoidAgent};
	if (! $@) {
		$ua=LWPx::ParanoidAgent->new;
	}
	else {
	        $ua=LWP::UserAgent->new;
	}

	# Store the secret in the session.
	my $secret=$session->param("openid_secret");
	if (! defined $secret) {
		$secret=rand;
		$session->param(openid_secret => $secret);
	}

	return Net::OpenID::Consumer->new(
		ua => $ua,
		args => $q,
		consumer_secret => sub { return shift()+$secret },
		required_root => $config{cgiurl},
	);
}

1
