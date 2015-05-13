#!/usr/bin/perl
# OpenID support.
package IkiWiki::Plugin::openid;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	add_underlay("openid-selector");
	add_underlay("jquery");
	hook(type => "checkconfig", id => "openid", call => \&checkconfig);
	hook(type => "getsetup", id => "openid", call => \&getsetup);
	hook(type => "auth", id => "openid", call => \&auth);
	hook(type => "formbuilder_setup", id => "openid",
		call => \&formbuilder_setup, last => 1);
}

sub checkconfig () {
	if ($config{cgi}) {
		# Intercept normal signin form, so the openid selector
		# can be displayed.
		# 
		# When other auth hooks are registered, give the selector
		# a reference to the normal signin form.
		require IkiWiki::CGI;
		my $real_cgi_signin;
		my $otherform_label=gettext("Other");
		if (keys %{$IkiWiki::hooks{auth}} > 1) {
			$real_cgi_signin=\&IkiWiki::cgi_signin;
			my %h=%{$IkiWiki::hooks{auth}};
			delete $h{openid};
			delete $h{emailauth};
			if (keys %h == 1 && exists $h{passwordauth}) {
				$otherform_label=gettext("Password");
			}
		}
		inject(name => "IkiWiki::cgi_signin", call => sub ($$) {
			openid_selector($real_cgi_signin, $otherform_label, @_);
		});
	}
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 0,
			section => "auth",
		},
		openid_realm => {
			type => "string",
			description => "url pattern of openid realm (default is cgiurl)",
			safe => 0,
			rebuild => 0,
		},
		openid_cgiurl => {
			type => "string",
			description => "url to ikiwiki cgi to use for openid authentication (default is cgiurl)",
			safe => 0,
			rebuild => 0,
		},
}

sub openid_selector {
	my $real_cgi_signin=shift;
	my $otherform_label=shift;
        my $q=shift;
        my $session=shift;

	my $template=IkiWiki::template("openid-selector.tmpl");
	my $openid_url=$q->param('openid_identifier');

	if (! load_openid_module()) {
		if ($real_cgi_signin) {
			$real_cgi_signin->($q, $session);
			exit;
		}
		error(sprintf(gettext("failed to load openid module: "), @_));
	}
	elsif (defined $q->param("action") && $q->param("action") eq "verify" && defined $openid_url && length $openid_url) {
		validate($q, $session, $openid_url, sub {
			$template->param(login_error => shift())
		});
	}

	$template->param(
		cgiurl => IkiWiki::cgiurl(),
		(defined $openid_url ? (openid_url => $openid_url) : ()),
		($real_cgi_signin ? (otherform => $real_cgi_signin->($q, $session, 1)) : ()),
		otherform_label => $otherform_label,
		login_selector_openid => 1,
		login_selector_email => 1,
	);

	IkiWiki::printheader($session);
	print IkiWiki::cgitemplate($q, "signin", $template->output);
	exit;
}

sub formbuilder_setup (@) {
	my %params=@_;

	my $form=$params{form};
	my $session=$params{session};
	my $cgi=$params{cgi};
	
	if ($form->title eq "preferences" &&
	       IkiWiki::openiduser($session->param("name"))) {
		$form->field(name => "openid_identifier", disabled => 1,
			label => htmllink("", "", "ikiwiki/OpenID", noimageinline => 1),
			value => "", 
			size => 1, force => 1,
			fieldset => "login",
			comment => $session->param("name"));
	}
}

sub validate ($$$;$) {
	my $q=shift;
	my $session=shift;
	my $openid_url=shift;
	my $errhandler=shift;

	my $csr=getobj($q, $session);

	my $claimed_identity = $csr->claimed_identity($openid_url);
	if (! $claimed_identity) {
		if ($errhandler) {
			if (ref($errhandler) eq 'CODE') {
				$errhandler->($csr->err);
			}
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

	my $cgiurl=$config{openid_cgiurl};
	$cgiurl=$q->url if ! defined $cgiurl;

	my $trust_root=$config{openid_realm};
	$trust_root=$cgiurl if ! defined $trust_root;

	my $check_url = $claimed_identity->check_url(
		return_to => auto_upgrade_https($q, "$cgiurl?do=postsignin"),
		trust_root => auto_upgrade_https($q, $trust_root),
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
			IkiWiki::redirect($q, IkiWiki::baseurl(undef));
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
			my $nickname;
			foreach my $ext (@extensions) {
				foreach my $field (qw{value.email email}) {
					if (exists $ext->{$field} &&
					    defined $ext->{$field} &&
					    length $ext->{$field}) {
						$session->param(email => $ext->{$field});
						if (! defined $nickname &&
						    $ext->{$field}=~/(.+)@.+/) {
							$nickname = $1;
						}
						last;
					}
				}
				foreach my $field (qw{value.nickname nickname value.fullname fullname value.firstname}) {
					if (exists $ext->{$field} &&
					    defined $ext->{$field} &&
					    length $ext->{$field}) {
						$nickname=$ext->{$field};
						last;
					}
				}
			}
			if (defined $nickname) {
				$session->param(nickname =>
					Encode::decode_utf8($nickname));
			}
		}
		else {
			error("OpenID failure: ".$csr->err);
		}
	}
	elsif (defined $q->param('openid_identifier')) {
		# myopenid.com affiliate support
		validate($q, $session, scalar $q->param('openid_identifier'));
	}
}

sub getobj ($$) {
	my $q=shift;
	my $session=shift;

	eval q{use Net::INET6Glue::INET_is_INET6}; # may not be available
	eval q{use Net::OpenID::Consumer};
	error($@) if $@;

	my $ua;
	eval q{use LWPx::ParanoidAgent};
	if (! $@) {
		$ua=LWPx::ParanoidAgent->new(agent => $config{useragent});
	}
	else {
		$ua=useragent();
	}

	# Store the secret in the session.
	my $secret=$session->param("openid_secret");
	if (! defined $secret) {
		$secret=rand;
		$session->param(openid_secret => $secret);
	}
	
	my $cgiurl=$config{openid_cgiurl};
	$cgiurl=$q->url if ! defined $cgiurl;

	return Net::OpenID::Consumer->new(
		ua => $ua,
		args => $q,
		consumer_secret => sub { return shift()+$secret },
		required_root => auto_upgrade_https($q, $cgiurl),
	);
}

sub auto_upgrade_https {
	my $q=shift;
	my $url=shift;
	if ($q->https()) {
		$url=~s/^http:/https:/i;
	}
	return $url;
}

sub load_openid_module {
	# Give up if module is unavailable to avoid needing to depend on it.
	eval q{use Net::OpenID::Consumer};
	if ($@) {
		debug("unable to load Net::OpenID::Consumer, not enabling OpenID login ($@)");
		return;
	}
	return 1;
}

1
