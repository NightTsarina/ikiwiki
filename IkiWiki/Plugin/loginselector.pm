#!/usr/bin/perl
package IkiWiki::Plugin::loginselector;

use warnings;
use strict;
use IkiWiki 3.00;

# Plugins that provide login methods can register themselves here.
# Note that the template and js file also have be be modifed to add a new
# login method.
our %login_plugins;

sub register_login_plugin ($$$$) {
	# Same as the name of the plugin that is registering itself as a
	# login plugin. eg, "openid"
	my $plugin_name=shift;
	# This sub is passed a cgi object and a template object which it
	# can manipulate. It should return true if the plugin can be used
	# (it might load necessary modules for auth checking, for example).
	my $plugin_setup=shift;
	# This sub is passed a cgi object, and should return true
	# if it looks like the user is logging in using the plugin.
	my $plugin_check_input=shift;
	# This sub is passed a cgi object, a session object, and an error
	# display callback, and should handle the actual authentication.
	# It can either exit w/o returning, if it is able to handle
	# auth, or it can pass an error message to the error display
	# callback to make the openid selector form be re-disiplayed with
	# an error message on it.
	my $plugin_auth=shift;
	$login_plugins{$plugin_name}={
		setup => $plugin_setup,
		check_input => $plugin_check_input,
		auth => $plugin_auth,
	};
}

sub login_selector {
	my $real_cgi_signin=shift;
	my $otherform_label=shift;
	my $q=shift;
	my $session=shift;

	my $template=IkiWiki::template("login-selector.tmpl");

	foreach my $plugin (keys %login_plugins) {
		if (! $login_plugins{$plugin}->{setup}->($template)) {
			delete $login_plugins{$plugin};
		}
		else {
			$template->param("login_selector_$plugin", 1);
		}
	}

	foreach my $plugin (keys %login_plugins) {
		if ($login_plugins{$plugin}->{check_input}->($q)) {
			$login_plugins{$plugin}->{auth}->($q, $session, sub {
				$template->param(login_error => shift());
			});
			last;
		}
	}

	$template->param(
		cgiurl => IkiWiki::cgiurl(),
		($real_cgi_signin ? (otherform => $real_cgi_signin->($q, $session, 1)) : ()),
		otherform_label => $otherform_label,
	);

	IkiWiki::printheader($session);
	print IkiWiki::cgitemplate($q, "signin", $template->output);
	exit;
}

sub import {
	add_underlay("login-selector");
	add_underlay("jquery");
	hook(type => "getsetup", id => "loginselector",  call => \&getsetup);
	hook(type => "checkconfig", id => "loginselector", call => \&checkconfig);
	hook(type => "auth", id => "loginselector", call => \&authstub);
}

sub checkconfig () {
	if ($config{cgi}) {
		# Intercept normal signin form, so the login selector
		# can be displayed.
		# 
		# When other auth hooks are registered, give the selector
		# a reference to the normal signin form.
		require IkiWiki::CGI;
		my $real_cgi_signin;
		my $otherform_label=gettext("Other");
		if (keys %{$IkiWiki::hooks{auth}} > 1) {
			$real_cgi_signin=\&IkiWiki::cgi_signin;
			# Special case to avoid labeling password auth as
			# "Other" when it's the only auth plugin not
			# integrated with the loginselector.
			my %h=%{$IkiWiki::hooks{auth}};
			foreach my $p (keys %login_plugins) {
				delete $h{$p};
			}
			delete $h{loginselector};
			if (keys %h == 1 && exists $h{passwordauth}) {
				$otherform_label=gettext("Password");
			}
		}
		inject(name => "IkiWiki::cgi_signin", call => sub ($$) {
			login_selector($real_cgi_signin, $otherform_label, @_);
		});
	}
}

sub getsetup () {
	return
		plugin => {
			# this plugin is safe but only makes sense as a
			# dependency
			safe => 0,
			rebuild => 0,
		},
}

sub authstub ($$) {
	# While this hook is not currently used, it needs to exist
	# so ikiwiki knows that the wiki supports logins, and will
	# enable the Preferences page.
}

1
