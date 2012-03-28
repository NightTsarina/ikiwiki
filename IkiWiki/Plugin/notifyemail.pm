#!/usr/bin/perl
package IkiWiki::Plugin::notifyemail;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "formbuilder_setup", id => "notifyemail", call => \&formbuilder_setup);
	hook(type => "formbuilder", id => "notifyemail", call => \&formbuilder);
	hook(type => "getsetup", id => "notifyemail",  call => \&getsetup);
	hook(type => "changes", id => "notifyemail", call => \&notify);
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
	$form->field(name => "subscriptions", size => 50,
		fieldset => "preferences",
		comment => "(".htmllink("", "", "ikiwiki/PageSpec", noimageinline => 1).")",
		value => getsubscriptions($session->param("name")));
}

sub formbuilder (@) {
	my %params=@_;
	my $form=$params{form};
	return unless $form->title eq "preferences" &&
		$form->submitted eq "Save Preferences" && $form->validate &&
		defined $form->field("subscriptions");
	setsubscriptions($form->field('name'), $form->field('subscriptions'));
}

sub getsubscriptions ($) {
	my $user=shift;
	eval q{use IkiWiki::UserInfo};
	error $@ if $@;
	IkiWiki::userinfo_get($user, "subscriptions");
}

sub setsubscriptions ($$) {
	my $user=shift;
	my $subscriptions=shift;
	eval q{use IkiWiki::UserInfo};
	error $@ if $@;
	IkiWiki::userinfo_set($user, "subscriptions", $subscriptions);
}

# Called by other plugins to subscribe the user to a pagespec.
sub subscribe ($$) {
	my $user=shift;
	my $addpagespec=shift;
	my $pagespec=getsubscriptions($user);
	setsubscriptions($user, $pagespec." or ".$addpagespec);
}

sub notify (@) {
	my @files=@_;
	return unless @files;

	eval q{use Mail::Sendmail};
	error $@ if $@;
	eval q{use IkiWiki::UserInfo};
	error $@ if $@;
	eval q{use URI};
	error($@) if $@;

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
			my $content="";
			my $showcontent=defined pagetype($file);
			if ($showcontent) {
				$content=eval { readfile(srcfile($file)) };
				$showcontent=0 if $@;
			}
			my $url;
			if (! IkiWiki::isinternal($page)) {
				$url=urlto($page, undef, 1);
			}
			elsif (defined $pagestate{$page}{meta}{permalink}) {
				# need to use permalink for an internal page
				$url=URI->new_abs($pagestate{$page}{meta}{permalink}, $config{url});
			}
			else {
				$url=$config{url}; # crummy fallback url
			}
			my $pagedesc=$page;
			if (defined $pagestate{$page}{meta}{title} &&
			    length $pagestate{$page}{meta}{title}) {
				$pagedesc=qq{"$pagestate{$page}{meta}{title}"};
			}
			my $subject=gettext("change notification:")." ".$pagedesc;
			if (pagetype($file) eq '_comment') {
				$subject=gettext("comment notification:")." ".$pagedesc;
			}
			my $template=template("notifyemail.tmpl");
			$template->param(
				wikiname => $config{wikiname},
				url => $url,
				prefsurl => $config{cgiurl}."?do=prefs",
				showcontent => $showcontent,
				content => $content,
			);
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
