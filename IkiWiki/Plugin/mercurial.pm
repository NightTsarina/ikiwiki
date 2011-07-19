#!/usr/bin/perl
package IkiWiki::Plugin::mercurial;

use warnings;
use strict;
use IkiWiki;
use Encode;
use open qw{:utf8 :std};

sub import {
	hook(type => "checkconfig", id => "mercurial", call => \&checkconfig);
	hook(type => "getsetup", id => "mercurial", call => \&getsetup);
	hook(type => "rcs", id => "rcs_update", call => \&rcs_update);
	hook(type => "rcs", id => "rcs_prepedit", call => \&rcs_prepedit);
	hook(type => "rcs", id => "rcs_commit", call => \&rcs_commit);
	hook(type => "rcs", id => "rcs_commit_staged", call => \&rcs_commit_staged);
	hook(type => "rcs", id => "rcs_add", call => \&rcs_add);
	hook(type => "rcs", id => "rcs_remove", call => \&rcs_remove);
	hook(type => "rcs", id => "rcs_rename", call => \&rcs_rename);
	hook(type => "rcs", id => "rcs_recentchanges", call => \&rcs_recentchanges);
	hook(type => "rcs", id => "rcs_diff", call => \&rcs_diff);
	hook(type => "rcs", id => "rcs_getctime", call => \&rcs_getctime);
	hook(type => "rcs", id => "rcs_getmtime", call => \&rcs_getmtime);
}

sub checkconfig () {
	if (exists $config{mercurial_wrapper} && length $config{mercurial_wrapper}) {
		push @{$config{wrappers}}, {
			wrapper => $config{mercurial_wrapper},
			wrappermode => (defined $config{mercurial_wrappermode} ? $config{mercurial_wrappermode} : "06755"),
		};
	}
}

sub getsetup () {
	return
		plugin => {
			safe => 0, # rcs plugin
			rebuild => undef,
			section => "rcs",
		},
		mercurial_wrapper => {
			type => "string",
			#example => # FIXME add example
			description => "mercurial post-commit hook to generate",
			safe => 0, # file
			rebuild => 0,
		},
		mercurial_wrappermode => {
			type => "string",
			example => '06755',
			description => "mode for mercurial_wrapper (can safely be made suid)",
			safe => 0,
			rebuild => 0,
		},
		historyurl => {
			type => "string",
			example => "http://example.com:8000/log/tip/[[file]]",
			description => "url to hg serve'd repository, to show file history ([[file]] substituted)",
			safe => 1,
			rebuild => 1,
		},
		diffurl => {
			type => "string",
			example => "http://localhost:8000/?fd=[[r2]];file=[[file]]",
			description => "url to hg serve'd repository, to show diff ([[file]] and [[r2]] substituted)",
			safe => 1,
			rebuild => 1,
		},
}

sub safe_hg (&@) {
	# Start a child process safely without resorting to /bin/sh.
	# Returns command output (in list content) or success state
	# (in scalar context), or runs the specified data handler.

	my ($error_handler, $data_handler, @cmdline) = @_;

	my $pid = open my $OUT, "-|";

	error("Cannot fork: $!") if !defined $pid;

	if (!$pid) {
		# In child.
		# hg commands want to be in wc.
		chdir $config{srcdir}
		    or error("cannot chdir to $config{srcdir}: $!");

		exec @cmdline or error("Cannot exec '@cmdline': $!");
	}
	# In parent.

	my @lines;
	while (<$OUT>) {
		chomp;

		if (! defined $data_handler) {
			push @lines, $_;
		}
		else {
			last unless $data_handler->($_);
		}
	}

	close $OUT;

	$error_handler->("'@cmdline' failed: $!") if $? && $error_handler;

	return wantarray ? @lines : ($? == 0);
}
# Convenient wrappers.
sub run_or_die ($@) { safe_hg(\&error, undef, @_) }
sub run_or_cry ($@) { safe_hg(sub { warn @_ }, undef, @_) }
sub run_or_non ($@) { safe_hg(undef, undef, @_) }

sub mercurial_log ($) {
	my $out = shift;
	my @infos;

	while (<$out>) {
		my $line = $_;
		my ($key, $value);

		if (/^description:/) {
			$key = "description";
			$value = "";

			# slurp everything as the description text 
			# until the next changeset
			while (<$out>) {
				if (/^changeset: /) {
					$line = $_;
					last;
				}

				$value .= $_;
			}

			local $/ = "";
			chomp $value;
			$infos[$#infos]{$key} = $value;
		}

		chomp $line;
	        ($key, $value) = split /: +/, $line, 2;

		if ($key eq "changeset") {
			push @infos, {};

			# remove the revision index, which is strictly 
			# local to the repository
			$value =~ s/^\d+://;
		}

		$infos[$#infos]{$key} = $value;
	}
	close $out;

	return @infos;
}

sub rcs_update () {
	run_or_cry('hg', '-q', 'update');
}

sub rcs_prepedit ($) {
	return "";
}

sub rcs_commit (@) {
	my %params=@_;

	return rcs_commit_helper(@_);
}

sub rcs_commit_helper (@) {
	my %params=@_;

	my %env=%ENV;
	$ENV{HGENCODING} = 'utf-8';

	my $user="Anonymous";
	my $nickname;
	if (defined $params{session}) {
		if (defined $params{session}->param("name")) {
			$user = $params{session}->param("name");
		}
		elsif (defined $params{session}->remote_addr()) {
			$user = $params{session}->remote_addr();
		}

		if (defined $params{session}->param("nickname")) {
			$nickname=encode_utf8($params{session}->param("nickname"));
			$nickname=~s/\s+/_/g;
			$nickname=~s/[^-_0-9[:alnum:]]+//g;
		}
		$ENV{HGUSER} = encode_utf8($user . ' <' . $nickname . '@web>');
	}

	if (! length $params{message}) {
		$params{message} = "no message given";
	}

	$params{message} = IkiWiki::possibly_foolish_untaint($params{message});

	my @opts;

	if (exists $params{file}) {
		push @opts, '--', $params{file};
	}
	# hg commit returns non-zero if nothing really changed.
	# So we should ignore its exit status (hence run_or_non).
	run_or_non('hg', 'commit', '-m', $params{message}, '-q', @opts);

	%ENV=%env;
	return undef; # success
}

sub rcs_commit_staged (@) {
	# Commits all staged changes. Changes can be staged using rcs_add,
	# rcs_remove, and rcs_rename.
	return rcs_commit_helper(@_);
}

sub rcs_add ($) {
	my ($file) = @_;

	run_or_cry('hg', 'add', $file);
}

sub rcs_remove ($) {
	# Remove file from archive.
	my ($file) = @_;

	run_or_cry('hg', 'remove', '-f', $file);
}

sub rcs_rename ($$) {
	my ($src, $dest) = @_;

	run_or_cry('hg', 'rename', '-f', $src, $dest);
}

sub rcs_recentchanges ($) {
	my ($num) = @_;

	my %env=%ENV;
	$ENV{HGENCODING} = 'utf-8';

	my @cmdline = ("hg", "-R", $config{srcdir}, "log", "-v", "-l", $num,
		"--style", "default");
	open (my $out, "@cmdline |");

	eval q{use Date::Parse};
	error($@) if $@;

	my @ret;
	foreach my $info (mercurial_log($out)) {
		my @pages = ();
		my @message = ();
        
		foreach my $msgline (split(/\n/, $info->{description})) {
			push @message, { line => $msgline };
		}

		foreach my $file (split / /,$info->{files}) {
			my $diffurl = defined $config{diffurl} ? $config{'diffurl'} : "";
			$diffurl =~ s/\[\[file\]\]/$file/go;
			$diffurl =~ s/\[\[r2\]\]/$info->{changeset}/go;

			push @pages, {
				page => pagename($file),
				diffurl => $diffurl,
			};
		}

		#"user <email@domain.net>": parse out "user".
		my $user = $info->{"user"};
		$user =~ s/\s*<.*>\s*$//;
		$user =~ s/^\s*//;

		#"user <nickname@web>": if "@web" hits, set $web_commit=true.
		my $web_commit = ($info->{'user'} =~ /\@web>/);

		#"user <nickname@web>": if user is a URL (hits "://") and "@web"
		#was present, parse out nick.
		my $nickname;
		if ($user =~ /:\/\// && $web_commit) {
			$nickname = $info->{'user'};
			$nickname =~ s/^[^<]*<([^\@]+)\@web>\s*$/$1/;
		}

		push @ret, {
			rev        => $info->{"changeset"},
			user       => $user,
			nickname   => $nickname,
			committype => $web_commit ? "web" : "hg",
			when       => str2time($info->{"date"}),
			message    => [@message],
			pages      => [@pages],
		};
	}

	%ENV=%env;

	return @ret;
}

sub rcs_diff ($;$) {
	# TODO
}

sub rcs_getctime ($) {
	my ($file) = @_;

	my @cmdline = ("hg", "-R", $config{srcdir}, "log", "-v",
		"--style", "default", "$config{srcdir}/$file");
	open (my $out, "-|", @cmdline);

	my @log = (mercurial_log($out));

	if (@log < 1) {
		return 0;
	}

	eval q{use Date::Parse};
	error($@) if $@;
	
	my $ctime = str2time($log[$#log]->{"date"});
	return $ctime;
}

sub rcs_getmtime ($) {
	error "rcs_getmtime is not implemented for mercurial\n"; # TODO
}

1
