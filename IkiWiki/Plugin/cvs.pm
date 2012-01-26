#!/usr/bin/perl
package IkiWiki::Plugin::cvs;

# Copyright (c) 2009 Amitai Schlair
# All rights reserved.
#
# This code is derived from software contributed to ikiwiki
# by Amitai Schlair.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY IKIWIKI AND CONTRIBUTORS ``AS IS''
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
# TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
# PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE FOUNDATION
# OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF
# USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT
# OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.

use warnings;
use strict;
use IkiWiki;

use File::chdir;


# GENERAL PLUGIN API CALLS

sub import {
	hook(type => "checkconfig", id => "cvs", call => \&checkconfig);
	hook(type => "getsetup", id => "cvs", call => \&getsetup);
	hook(type => "genwrapper", id => "cvs", call => \&genwrapper);

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
	if (! defined $config{cvspath}) {
		$config{cvspath}="ikiwiki";
	}
	if (exists $config{cvspath}) {
		# code depends on the path not having extraneous slashes
		$config{cvspath}=~tr#/#/#s;
		$config{cvspath}=~s/\/$//;
		$config{cvspath}=~s/^\///;
	}
	if (defined $config{cvs_wrapper} && length $config{cvs_wrapper}) {
		push @{$config{wrappers}}, {
			wrapper => $config{cvs_wrapper},
			wrappermode => (defined $config{cvs_wrappermode} ? $config{cvs_wrappermode} : "04755"),
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
		cvsrepo => {
			type => "string",
			example => "/cvs/wikirepo",
			description => "cvs repository location",
			safe => 0, # path
			rebuild => 0,
		},
		cvspath => {
			type => "string",
			example => "ikiwiki",
			description => "path inside repository where the wiki is located",
			safe => 0, # paranoia
			rebuild => 0,
		},
		cvs_wrapper => {
			type => "string",
			example => "/cvs/wikirepo/CVSROOT/post-commit",
			description => "cvs post-commit hook to generate (triggered by CVSROOT/loginfo entry)",
			safe => 0, # file
			rebuild => 0,
		},
		cvs_wrappermode => {
			type => "string",
			example => '04755',
			description => "mode for cvs_wrapper (can safely be made suid)",
			safe => 0,
			rebuild => 0,
		},
		historyurl => {
			type => "string",
			example => "http://cvs.example.org/cvsweb.cgi/ikiwiki/[[file]]",
			description => "cvsweb url to show file history ([[file]] substituted)",
			safe => 1,
			rebuild => 1,
		},
		diffurl => {
			type => "string",
			example => "http://cvs.example.org/cvsweb.cgi/ikiwiki/[[file]].diff?r1=text&amp;tr1=[[r1]]&amp;r2=text&amp;tr2=[[r2]]",
			description => "cvsweb url to show a diff ([[file]], [[r1]], and [[r2]] substituted)",
			safe => 1,
			rebuild => 1,
		},
}

sub genwrapper () {
	return <<EOF;
	{
		int j;
		for (j = 1; j < argc; j++)
			if (strstr(argv[j], "New directory") != NULL)
				exit(0);
	}
EOF
}


# VCS PLUGIN API CALLS

sub rcs_update () {
	return unless cvs_is_controlling();
	cvs_runcvs('update', '-dP');
}

sub rcs_prepedit ($) {
	# Prepares to edit a file under revision control. Returns a token
	# that must be passed into rcs_commit when the file is ready
	# for committing.
	# The file is relative to the srcdir.
	my $file=shift;

	return unless cvs_is_controlling();

	# For cvs, return the revision of the file when
	# editing begins.
	my $rev=cvs_info("Repository revision", "$file");
	return defined $rev ? $rev : "";
}

sub rcs_commit (@) {
	# Tries to commit the page; returns undef on _success_ and
	# a version of the page with the rcs's conflict markers on failure.
	# The file is relative to the srcdir.
	my %params=@_;

	return unless cvs_is_controlling();

	# Check to see if the page has been changed by someone
	# else since rcs_prepedit was called.
	my ($oldrev)=$params{token}=~/^([0-9]+)$/; # untaint
	my $rev=cvs_info("Repository revision", "$config{srcdir}/$params{file}");
	if (defined $rev && defined $oldrev && $rev != $oldrev) {
		# Merge their changes into the file that we've
		# changed.
		cvs_runcvs('update', $params{file}) ||
			warn("cvs merge from $oldrev to $rev failed\n");
	}

	if (! cvs_runcvs('commit', '-m',
			 IkiWiki::possibly_foolish_untaint(commitmessage(%params)))) {
		my $conflict=readfile("$config{srcdir}/$params{file}");
		cvs_runcvs('update', '-C', $params{file}) ||
			warn("cvs revert failed\n");
		return $conflict;
	}

	return undef # success
}

sub rcs_commit_staged (@) {
	# Commits all staged changes. Changes can be staged using rcs_add,
	# rcs_remove, and rcs_rename.
	my %params=@_;

	if (! cvs_runcvs('commit', '-m',
			 IkiWiki::possibly_foolish_untaint(commitmessage(%params)))) {
		warn "cvs staged commit failed\n";
		return 1; # failure
	}
	return undef # success
}

sub rcs_add ($) {
	# filename is relative to the root of the srcdir
	my $file=shift;
	my $parent=IkiWiki::dirname($file);
	my @files_to_add = ($file);

	eval q{use File::MimeInfo};
	error($@) if $@;

	until ((length($parent) == 0) || cvs_is_controlling("$config{srcdir}/$parent")){
		push @files_to_add, $parent;
		$parent = IkiWiki::dirname($parent);
	}

	while ($file = pop @files_to_add) {
		if (@files_to_add == 0) {
			# file
			my $filemime = File::MimeInfo::default($file);
			if (defined($filemime) && $filemime eq 'text/plain') {
				cvs_runcvs('add', $file) ||
					warn("cvs add $file failed\n");
			}
			else {
				cvs_runcvs('add', '-kb', $file) ||
					warn("cvs add binary $file failed\n");
			}
		}
		else {
			# directory
			cvs_runcvs('add', $file) ||
				warn("cvs add $file failed\n");
		}
	}
}

sub rcs_remove ($) {
	# filename is relative to the root of the srcdir
	my $file=shift;

	return unless cvs_is_controlling();

	cvs_runcvs('rm', '-f', $file) ||
		warn("cvs rm $file failed\n");
}

sub rcs_rename ($$) {
	# filenames relative to the root of the srcdir
	my ($src, $dest)=@_;

	return unless cvs_is_controlling();

	local $CWD = $config{srcdir};

	if (system("mv", "$src", "$dest") != 0) {
		warn("filesystem rename failed\n");
	}

	rcs_add($dest);
	rcs_remove($src);
}

sub rcs_recentchanges ($) {
	my $num = shift;
	my @ret;

	return unless cvs_is_controlling();

	eval q{use Date::Parse};
	error($@) if $@;

	local $CWD = $config{srcdir};

	# There's no cvsps option to get the last N changesets.
	# Write full output to a temp file and read backwards.

	eval q{use File::Temp qw/tempfile/};
	error($@) if $@;
	eval q{use File::ReadBackwards};
	error($@) if $@;

	my ($tmphandle, $tmpfile) = tempfile();
	system("env TZ=UTC cvsps -q --cvs-direct -z 30 -x >$tmpfile");
	if ($? == -1) {
		error "couldn't run cvsps: $!\n";
	}
	elsif (($? >> 8) != 0) {
		error "cvsps exited " . ($? >> 8) . ": $!\n";
	}

	tie(*SPSVC, 'File::ReadBackwards', $tmpfile)
		|| error "couldn't open $tmpfile for read: $!\n";

	while (my $line = <SPSVC>) {
		$line =~ /^$/ || error "expected blank line, got $line";

		my ($rev, $user, $committype, $when);
		my (@message, @pages);

		# We're reading backwards.
		# Forwards, an entry looks like so:
		# ---------------------
		# PatchSet $rev
		# Date: $when
		# Author: $user (or user CGI runs as, for web commits)
		# Branch: branch
		# Tag: tag
		# Log:
		# @message_lines
		# Members:
		#	@pages (and revisions)
		#

		while ($line = <SPSVC>) {
			last if ($line =~ /^Members:/);
			for ($line) {
				s/^\s+//;
				s/\s+$//;
			}
			my ($page, $revs) = split(/:/, $line);
			my ($oldrev, $newrev) = split(/->/, $revs);
			$oldrev =~ s/INITIAL/0/;
			$newrev =~ s/\(DEAD\)//;
			my $diffurl = defined $config{diffurl} ? $config{diffurl} : "";
			$diffurl=~s/\[\[file\]\]/$page/g;
			$diffurl=~s/\[\[r1\]\]/$oldrev/g;
			$diffurl=~s/\[\[r2\]\]/$newrev/g;
			unshift @pages, {
				page => pagename($page),
				diffurl => $diffurl,
			} if length $page;
		}

		while ($line = <SPSVC>) {
			last if ($line =~ /^Log:$/);
			chomp $line;
			unshift @message, { line => $line };
		}
		$committype = "web";
		if (defined $message[0] &&
		    $message[0]->{line}=~/$config{web_commit_regexp}/) {
			$user=defined $2 ? "$2" : "$3";
			$message[0]->{line}=$4;
		}
		else {
			$committype="cvs";
		}

		$line = <SPSVC>;	# Tag
		$line = <SPSVC>;	# Branch

		$line = <SPSVC>;
		if ($line =~ /^Author: (.*)$/) {
			$user = $1 unless defined $user && length $user;
		}
		else {
			error "expected Author, got $line";
		}

		$line = <SPSVC>;
		if ($line =~ /^Date: (.*)$/) {
			$when = str2time($1, 'UTC');
		}
		else {
			error "expected Date, got $line";
		}

		$line = <SPSVC>;
		if ($line =~ /^PatchSet (.*)$/) {
			$rev = $1;
		}
		else {
			error "expected PatchSet, got $line";
		}

		$line = <SPSVC>;	# ---------------------

		push @ret, {
			rev => $rev,
			user => $user,
			committype => $committype,
			when => $when,
			message => [@message],
			pages => [@pages],
		} if @pages;
		last if @ret >= $num;
	}

	unlink($tmpfile) || error "couldn't unlink $tmpfile: $!\n";

	return @ret;
}

sub rcs_diff ($;$) {
	my $rev=IkiWiki::possibly_foolish_untaint(int(shift));
	my $maxlines=shift;

	local $CWD = $config{srcdir};

	# diff output is unavoidably preceded by the cvsps PatchSet entry
	my @cvsps = `env TZ=UTC cvsps -q --cvs-direct -z 30 -g -s $rev`;
	my $blank_lines_seen = 0;

	while (my $line = shift @cvsps) {
		$blank_lines_seen++ if ($line =~ /^$/);
		last if $blank_lines_seen == 2;
	}

	if (wantarray) {
		return @cvsps;
	}
	else {
		return join("", @cvsps);
	}
}

sub rcs_getctime ($) {
	my $file=shift;

	local $CWD = $config{srcdir};

	my $cvs_log_infoline=qr/^date: (.+);\s+author/;

	open CVSLOG, "cvs -Q log -r1.1 '$file' |"
		|| error "couldn't get cvs log output: $!\n";

	my $date;
	while (<CVSLOG>) {
		if (/$cvs_log_infoline/) {
			$date=$1;
		}
	}
	close CVSLOG || warn "cvs log $file exited $?";

	if (! defined $date) {
		warn "failed to parse cvs log for $file\n";
		return 0;
	}

	eval q{use Date::Parse};
	error($@) if $@;
	$date=str2time($date, 'UTC');
	debug("found ctime ".localtime($date)." for $file");
	return $date;
}

sub rcs_getmtime ($) {
	error "rcs_getmtime is not implemented for cvs\n"; # TODO
}


# INTERNAL SUPPORT ROUTINES

sub commitmessage (@) {
	my %params=@_;

	if (defined $params{session}) {
		if (defined $params{session}->param("name")) {
			return "web commit by ".
				$params{session}->param("name").
				(length $params{message} ? ": $params{message}" : "");
		}
		elsif (defined $params{session}->remote_addr()) {
			return "web commit from ".
				$params{session}->remote_addr().
				(length $params{message} ? ": $params{message}" : "");
		}
	}
	return $params{message};
}

sub cvs_info ($$) {
	my $field=shift;
	my $file=shift;

	local $CWD = $config{srcdir};

	my $info=`cvs status $file`;
	my ($ret)=$info=~/^\s*$field:\s*(\S+)/m;
	return $ret;
}

sub cvs_is_controlling {
	my $dir=shift;
	$dir=$config{srcdir} unless defined($dir);
	return (-d "$dir/CVS") ? 1 : 0;
}

sub cvs_runcvs(@) {
	my @cmd = @_;
	unshift @cmd, 'cvs', '-Q';

	local $CWD = $config{srcdir};

	open(my $savedout, ">&STDOUT");
	open(STDOUT, ">", "/dev/null");
	my $ret = system(@cmd);
	open(STDOUT, ">&", $savedout);

	return ($ret == 0) ? 1 : 0;
}

1
