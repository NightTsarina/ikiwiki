#!/usr/bin/perl
package IkiWiki::Plugin::bzr;

use warnings;
use strict;
use IkiWiki;
use Encode;
use URI::Escape q{uri_escape_utf8};
use open qw{:utf8 :std};

sub import {
	hook(type => "checkconfig", id => "bzr", call => \&checkconfig);
	hook(type => "getsetup", id => "bzr", call => \&getsetup);
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
	if (defined $config{bzr_wrapper} && length $config{bzr_wrapper}) {
		push @{$config{wrappers}}, {
			wrapper => $config{bzr_wrapper},
			wrappermode => (defined $config{bzr_wrappermode} ? $config{bzr_wrappermode} : "06755"),
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
		bzr_wrapper => {
			type => "string",
			#example => "", # FIXME add example
			description => "bzr post-commit hook to generate",
			safe => 0, # file
			rebuild => 0,
		},
		bzr_wrappermode => {
			type => "string",
			example => '06755',
			description => "mode for bzr_wrapper (can safely be made suid)",
			safe => 0,
			rebuild => 0,
		},
		historyurl => {
			type => "string",
			#example => "", # FIXME add example
			description => "url to show file history, using loggerhead ([[file]] substituted)",
			safe => 1,
			rebuild => 1,
		},
		diffurl => {
			type => "string",
			example => "http://example.com/revision?start_revid=[[r2]]#[[file]]-s",
			description => "url to view a diff, using loggerhead ([[file]] and [[r2]] substituted)",
			safe => 1,
			rebuild => 1,
		},
}

sub bzr_log ($) {
	my $out = shift;
	my @infos = ();
	my $key = undef;

	my %info;
	while (<$out>) {
		my $line = $_;
		my ($value);
		if ($line =~ /^message:/) {
			$key = "message";
			$info{$key} = "";
		}
		elsif ($line =~ /^(modified|added|renamed|renamed and modified|removed):/) {
			$key = "files";
			$info{$key} = "" unless defined $info{$key};
		}
		elsif (defined($key) and $line =~ /^  (.*)/) {
			$info{$key} .= "$1\n";
		}
		elsif ($line eq "------------------------------------------------------------\n") {
			push @infos, {%info} if keys %info;
			%info = ();
			$key = undef;
		}
		elsif ($line =~ /: /) {
			chomp $line;
			if ($line =~ /^revno: (\d+)/) {
			    $key = "revno";
			    $value = $1;
			}
			else {
				($key, $value) = split /: +/, $line, 2;
			}
			$info{$key} = $value;
		}
	}
	close $out;
	push @infos, {%info} if keys %info;

	return @infos;
}

sub rcs_update () {
	my @cmdline = ("bzr", "update", "--quiet", $config{srcdir});
	if (system(@cmdline) != 0) {
		warn "'@cmdline' failed: $!";
	}
}

sub rcs_prepedit ($) {
	return "";
}

sub bzr_author ($) {
	my $session=shift;

	return unless defined $session;

	my $user=$session->param("name");
	my $ipaddr=$session->remote_addr();

	if (defined $user) {
		return IkiWiki::possibly_foolish_untaint($user);
	}
	elsif (defined $ipaddr) {
		return "Anonymous from ".IkiWiki::possibly_foolish_untaint($ipaddr);
	}
	else {
		return "Anonymous";
	}
}

sub rcs_commit (@) {
	my %params=@_;

	my $user=bzr_author($params{session});

	$params{message} = IkiWiki::possibly_foolish_untaint($params{message});
	if (! length $params{message}) {
		$params{message} = "no message given";
	}

	my @cmdline = ("bzr", "commit", "--quiet", "-m", $params{message},
	               (defined $user ? ("--author", $user) : ()),
	               $config{srcdir}."/".$params{file});
	if (system(@cmdline) != 0) {
		warn "'@cmdline' failed: $!";
	}

	return undef; # success
}

sub rcs_commit_staged (@) {
	my %params=@_;

	my $user=bzr_author($params{session});

	$params{message} = IkiWiki::possibly_foolish_untaint($params{message});
	if (! length $params{message}) {
		$params{message} = "no message given";
	}

	my @cmdline = ("bzr", "commit", "--quiet", "-m", $params{message},
	               (defined $user ? ("--author", $user) : ()),
	               $config{srcdir});
	if (system(@cmdline) != 0) {
		warn "'@cmdline' failed: $!";
	}

	return undef; # success
}

sub rcs_add ($) {
	my ($file) = @_;

	my @cmdline = ("bzr", "add", "--quiet", "$config{srcdir}/$file");
	if (system(@cmdline) != 0) {
		warn "'@cmdline' failed: $!";
	}
}

sub rcs_remove ($) {
	my ($file) = @_;

	my @cmdline = ("bzr", "rm", "--force", "--quiet", "$config{srcdir}/$file");
	if (system(@cmdline) != 0) {
		warn "'@cmdline' failed: $!";
	}
}

sub rcs_rename ($$) {
	my ($src, $dest) = @_;

	my $parent = IkiWiki::dirname($dest);
	if (system("bzr", "add", "--quiet", "$config{srcdir}/$parent") != 0) {
		warn("bzr add $parent failed\n");
	}

	my @cmdline = ("bzr", "mv", "--quiet", "$config{srcdir}/$src", "$config{srcdir}/$dest");
	if (system(@cmdline) != 0) {
		warn "'@cmdline' failed: $!";
	}
}

sub rcs_recentchanges ($) {
	my ($num) = @_;

	my @cmdline = ("bzr", "log", "-v", "--show-ids", "--limit", $num, 
		           $config{srcdir});
	open (my $out, "@cmdline |");

	eval q{use Date::Parse};
	error($@) if $@;

	my @ret;
	foreach my $info (bzr_log($out)) {
		my @pages = ();
		my @message = ();

		foreach my $msgline (split(/\n/, $info->{message})) {
			push @message, { line => $msgline };
		}

		foreach my $file (split(/\n/, $info->{files})) {
			my ($filename, $fileid) = ($file =~ /^(.*?) +([^ ]+)$/);

			# Skip directories
			next if ($filename =~ /\/$/);

			# Skip source name in renames
			$filename =~ s/^.* => //;

			my $efilename = uri_escape_utf8($filename);

			my $diffurl = defined $config{'diffurl'} ? $config{'diffurl'} : "";
			$diffurl =~ s/\[\[file\]\]/$efilename/go;
			$diffurl =~ s/\[\[file-id\]\]/$fileid/go;
			$diffurl =~ s/\[\[r2\]\]/$info->{revno}/go;

			push @pages, {
				page => pagename($filename),
				diffurl => $diffurl,
			};
		}

		my $user = $info->{"committer"};
		if (defined($info->{"author"})) { $user = $info->{"author"}; }
		$user =~ s/\s*<.*>\s*$//;
		$user =~ s/^\s*//;

		push @ret, {
			rev        => $info->{"revno"},
			user       => $user,
			committype => "bzr",
			when       => str2time($info->{"timestamp"}),
			message    => [@message],
			pages      => [@pages],
		};
	}

	return @ret;
}

sub rcs_diff ($;$) {
	my $taintedrev=shift;
	my $maxlines=shift;
	my ($rev) = $taintedrev =~ /^(\d+(\.\d+)*)$/; # untaint

	my $prevspec = "before:" . $rev;
	my $revspec = "revno:" . $rev;
	my @cmdline = ("bzr", "diff", "--old", $config{srcdir},
		"--new", $config{srcdir},
		"-r", $prevspec . ".." . $revspec);
	open (my $out, "@cmdline |");
	my @lines;
	while (my $line=<$out>) {
		last if defined $maxlines && @lines == $maxlines;
		push @lines, $line;
	}
	if (wantarray) {
		return @lines;
	}
	else {
		return join("", @lines);
	}
}

sub extract_timestamp (@) {
	open (my $out, "-|", @_);
	my @log = bzr_log($out);

	if (length @log < 1) {
		return 0;
	}

	eval q{use Date::Parse};
	error($@) if $@;
	
	my $time = str2time($log[0]->{"timestamp"});
	return $time;
}

sub rcs_getctime ($) {
	my ($file) = @_;

	my @cmdline = ("bzr", "log", "--forward", "--limit", '1', "$config{srcdir}/$file");
	return extract_timestamp(@cmdline);
}

sub rcs_getmtime ($) {
	my ($file) = @_;

	my @cmdline = ("bzr", "log", "--limit", '1', "$config{srcdir}/$file");
	return extract_timestamp(@cmdline);
}

1
