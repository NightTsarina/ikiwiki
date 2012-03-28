#!/usr/bin/perl
package IkiWiki::Plugin::changemail;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "formbuilder_setup", id => "changemail", call => \&formbuilder_setup);
	hook(type => "formbuilder", id => "changemail", call => \&formbuilder);
	hook(type => "getsetup", id => "changemail",  call => \&getsetup);
	hook(type => "change", id => "changemail", call => \&notify);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 0,
			section => "misc",
		},
}

sub formbuilder_setup (@) {
	my %params=@_;

	my $form=$params{form};
	return unless $form->title eq "preferences";
	my $session=$params{session};
	my $user_name=$session->param("name");
	eval q{use IkiWiki::UserInfo};
	error $@ if $@;
	$form->field(name => "subscriptions", force => 1, size => 50,
		fieldset => "preferences",
		comment => "(".htmllink("", "", "ikiwiki/PageSpec", noimageinline => 1).")",
		value => IkiWiki::userinfo_get($user_name, "subscriptions"));
}

sub formbuilder (@) {
	my %params=@_;
	my $form=$params{form};
	return unless $form->title eq "preferences" &&
		$form->submitted eq "Save Preferences" && $form->validate &&
		defined $form->field("subscriptions");
	setsubscriptions($form->field('name'), $form->field('subscriptions'));
}

sub setsubscriptions ($$) {
	my $user=shift;
	my $subscriptions=shift;
	eval q{use IkiWiki::UserInfo};
	error $@ if $@;
	IkiWiki::userinfo_set($user, "subscriptions", $subscriptions);
}

sub notify (@) {
	my @files=@_;
	return unless @files;

	eval q{use Mail::Sendmail};
	error $@ if $@;
	eval q{use IkiWiki::UserInfo};
	error $@ if $@;

	# Daemonize, in case the mail sending takes a while.
	defined(my $pid = fork) or error("Can't fork: $!");
	return if $pid; # parent
	chdir '/';
	open STDIN, '/dev/null';
	open STDOUT, '>/dev/null';
	POSIX::setsid() or error("Can't start a new session: $!");
	open STDERR, '>&STDOUT' or error("Can't dup stdout: $!");

	# Don't need to keep a lock on the wiki as a daemon.
	IkiWiki::unlockwiki();

	my $userinfo=IkiWiki::userinfo_retrieve();
	exit 0 unless defined $userinfo;

	foreach my $user (keys %$userinfo) {
		my $pagespec=$userinfo->{$user}->{"subscriptions"};
		next unless defined $pagespec && length $pagespec;
		my $email=$userinfo->{$user}->{email};
		next unless defined $email && length $email;

		foreach my $file (@files) {
			my $page=pagename($file);
			next unless pagespec_match($page, $pagespec);
			my $ispage=defined pagetype($file);
			my $url;
			if (! IkiWiki::isinternal($page)) {
				$url=urlto($page, undef, 1);
			}
			elsif (defined $pagestate{$page}{meta}{permalink}) {
				# need to use permalink for an internal page
				$url=$pagestate{$page}{meta}{permalink};
			}
			else {
				$url=$config{wikiurl}; # crummy fallback url
			}
			my $template=template("changemail.tmpl");
			$template->param(
				wikiname => $config{wikiname},
				url => $url,
				prefsurl => IkiWiki::cgiurl(do => "prefs"),
				ispage => $ispage,
				content => $ispage ? readfile(srcfile($file)) : "",
			);
			#translators: The two variables are the name of the wiki,
			#translators: and a page that was changed.
			#translators: This is used as the subject of a commit email.
			my $subject=sprintf(gettext("%s: change notification for %s"),
				$config{wikiname}, $page);
			sendmail(
				To => $email,
				From => "$config{wikiname} <$config{adminemail}>",
				Subject => $subject,
				Message => $template->output,
			);
		}
	}

	exit 0; # daemon child
}

1
