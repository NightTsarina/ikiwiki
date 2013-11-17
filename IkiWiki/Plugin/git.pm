#!/usr/bin/perl
package IkiWiki::Plugin::git;

use warnings;
use strict;
use IkiWiki;
use Encode;
use URI::Escape q{uri_escape_utf8};
use open qw{:utf8 :std};

my $sha1_pattern     = qr/[0-9a-fA-F]{40}/; # pattern to validate Git sha1sums
my $dummy_commit_msg = 'dummy commit';      # message to skip in recent changes

sub import {
	hook(type => "checkconfig", id => "git", call => \&checkconfig);
	hook(type => "getsetup", id => "git", call => \&getsetup);
	hook(type => "genwrapper", id => "git", call => \&genwrapper);
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
	hook(type => "rcs", id => "rcs_receive", call => \&rcs_receive);
	hook(type => "rcs", id => "rcs_preprevert", call => \&rcs_preprevert);
	hook(type => "rcs", id => "rcs_revert", call => \&rcs_revert);
	hook(type => "rcs", id => "rcs_find_changes", call => \&rcs_find_changes);
	hook(type => "rcs", id => "rcs_get_current_rev", call => \&rcs_get_current_rev);
}

sub checkconfig () {
	if (! defined $config{gitorigin_branch}) {
		$config{gitorigin_branch}="origin";
	}
	if (! defined $config{gitmaster_branch}) {
		$config{gitmaster_branch}="master";
	}
	if (defined $config{git_wrapper} &&
	    length $config{git_wrapper}) {
		push @{$config{wrappers}}, {
			wrapper => $config{git_wrapper},
			wrappermode => (defined $config{git_wrappermode} ? $config{git_wrappermode} : "06755"),
			wrapper_background_command => $config{git_wrapper_background_command},
		};
	}

	if (defined $config{git_test_receive_wrapper} &&
	    length $config{git_test_receive_wrapper} &&
	    defined $config{untrusted_committers} &&
	    @{$config{untrusted_committers}}) {
		push @{$config{wrappers}}, {
			test_receive => 1,
			wrapper => $config{git_test_receive_wrapper},
			wrappermode => (defined $config{git_wrappermode} ? $config{git_wrappermode} : "06755"),
		};
	}

	# Avoid notes, parser does not handle and they only slow things down.
	$ENV{GIT_NOTES_REF}="";
	
	# Run receive test only if being called by the wrapper, and not
	# when generating same.
	if ($config{test_receive} && ! exists $config{wrapper}) {
		require IkiWiki::Receive;
		IkiWiki::Receive::test();
	}
}

sub getsetup () {
	return
		plugin => {
			safe => 0, # rcs plugin
			rebuild => undef,
			section => "rcs",
		},
		git_wrapper => {
			type => "string",
			example => "/git/wiki.git/hooks/post-update",
			description => "git hook to generate",
			safe => 0, # file
			rebuild => 0,
		},
		git_wrapper_background_command => {
			type => "string",
			example => "git push github",
			description => "shell command for git_wrapper to run, in the background",
			safe => 0, # command
			rebuild => 0,
		},
		git_wrappermode => {
			type => "string",
			example => '06755',
			description => "mode for git_wrapper (can safely be made suid)",
			safe => 0,
			rebuild => 0,
		},
		git_test_receive_wrapper => {
			type => "string",
			example => "/git/wiki.git/hooks/pre-receive",
			description => "git pre-receive hook to generate",
			safe => 0, # file
			rebuild => 0,
		},
		untrusted_committers => {
			type => "string",
			example => [],
			description => "unix users whose commits should be checked by the pre-receive hook",
			safe => 0,
			rebuild => 0,
		},
		historyurl => {
			type => "string",
			example => "http://git.example.com/gitweb.cgi?p=wiki.git;a=history;f=[[file]];hb=HEAD",
			description => "gitweb url to show file history ([[file]] substituted)",
			safe => 1,
			rebuild => 1,
		},
		diffurl => {
			type => "string",
			example => "http://git.example.com/gitweb.cgi?p=wiki.git;a=blobdiff;f=[[file]];h=[[sha1_to]];hp=[[sha1_from]];hb=[[sha1_commit]];hpb=[[sha1_parent]]",
			description => "gitweb url to show a diff ([[file]], [[sha1_to]], [[sha1_from]], [[sha1_commit]], and [[sha1_parent]] substituted)",
			safe => 1,
			rebuild => 1,
		},
		gitorigin_branch => {
			type => "string",
			example => "origin",
			description => "where to pull and push changes (set to empty string to disable)",
			safe => 0, # paranoia
			rebuild => 0,
		},
		gitmaster_branch => {
			type => "string",
			example => "master",
			description => "branch that the wiki is stored in",
			safe => 0, # paranoia
			rebuild => 0,
		},
}

sub genwrapper {
	if ($config{test_receive}) {
		require IkiWiki::Receive;
		return IkiWiki::Receive::genwrapper();
	}
	else {
		return "";
	}
}

my $git_dir=undef;
my $prefix=undef;

sub in_git_dir ($$) {
	$git_dir=shift;
	my @ret=shift->();
	$git_dir=undef;
	$prefix=undef;
	return @ret;
}

sub safe_git (&@) {
	# Start a child process safely without resorting to /bin/sh.
	# Returns command output (in list content) or success state
	# (in scalar context), or runs the specified data handler.

	my ($error_handler, $data_handler, @cmdline) = @_;

	my $pid = open my $OUT, "-|";

	error("Cannot fork: $!") if !defined $pid;

	if (!$pid) {
		# In child.
		# Git commands want to be in wc.
		if (! defined $git_dir) {
			chdir $config{srcdir}
			    or error("cannot chdir to $config{srcdir}: $!");
		}
		else {
			chdir $git_dir
			    or error("cannot chdir to $git_dir: $!");
		}
		exec @cmdline or error("Cannot exec '@cmdline': $!");
	}
	# In parent.

	# git output is probably utf-8 encoded, but may contain
	# other encodings or invalidly encoded stuff. So do not rely
	# on the normal utf-8 IO layer, decode it by hand.
	binmode($OUT);

	my @lines;
	while (<$OUT>) {
		$_=decode_utf8($_, 0);

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
sub run_or_die ($@) { safe_git(\&error, undef, @_) }
sub run_or_cry ($@) { safe_git(sub { warn @_ }, undef, @_) }
sub run_or_non ($@) { safe_git(undef, undef, @_) }


sub merge_past ($$$) {
	# Unlike with Subversion, Git cannot make a 'svn merge -rN:M file'.
	# Git merge commands work with the committed changes, except in the
	# implicit case of '-m' of git checkout(1).  So we should invent a
	# kludge here.  In principle, we need to create a throw-away branch
	# in preparing for the merge itself.  Since branches are cheap (and
	# branching is fast), this shouldn't cost high.
	#
	# The main problem is the presence of _uncommitted_ local changes.  One
	# possible approach to get rid of this situation could be that we first
	# make a temporary commit in the master branch and later restore the
	# initial state (this is possible since Git has the ability to undo a
	# commit, i.e. 'git reset --soft HEAD^').  The method can be summarized
	# as follows:
	#
	# 	- create a diff of HEAD:current-sha1
	# 	- dummy commit
	# 	- create a dummy branch and switch to it
	# 	- rewind to past (reset --hard to the current-sha1)
	# 	- apply the diff and commit
	# 	- switch to master and do the merge with the dummy branch
	# 	- make a soft reset (undo the last commit of master)
	#
	# The above method has some drawbacks: (1) it needs a redundant commit
	# just to get rid of local changes, (2) somewhat slow because of the
	# required system forks.  Until someone points a more straight method
	# (which I would be grateful) I have implemented an alternative method.
	# In this approach, we hide all the modified files from Git by renaming
	# them (using the 'rename' builtin) and later restore those files in
	# the throw-away branch (that is, we put the files themselves instead
	# of applying a patch).

	my ($sha1, $file, $message) = @_;

	my @undo;      # undo stack for cleanup in case of an error
	my $conflict;  # file content with conflict markers

	eval {
		# Hide local changes from Git by renaming the modified file.
		# Relative paths must be converted to absolute for renaming.
		my ($target, $hidden) = (
		    "$config{srcdir}/${file}", "$config{srcdir}/${file}.${sha1}"
		);
		rename($target, $hidden)
		    or error("rename '$target' to '$hidden' failed: $!");
		# Ensure to restore the renamed file on error.
		push @undo, sub {
			return if ! -e "$hidden"; # already renamed
			rename($hidden, $target)
			    or warn "rename '$hidden' to '$target' failed: $!";
		};

		my $branch = "throw_away_${sha1}"; # supposed to be unique

		# Create a throw-away branch and rewind backward.
		push @undo, sub { run_or_cry('git', 'branch', '-D', $branch) };
		run_or_die('git', 'branch', $branch, $sha1);

		# Switch to throw-away branch for the merge operation.
		push @undo, sub {
			if (!run_or_cry('git', 'checkout', $config{gitmaster_branch})) {
				run_or_cry('git', 'checkout','-f',$config{gitmaster_branch});
			}
		};
		run_or_die('git', 'checkout', $branch);

		# Put the modified file in _this_ branch.
		rename($hidden, $target)
		    or error("rename '$hidden' to '$target' failed: $!");

		# _Silently_ commit all modifications in the current branch.
		run_or_non('git', 'commit', '-m', $message, '-a');
		# ... and re-switch to master.
		run_or_die('git', 'checkout', $config{gitmaster_branch});

		# Attempt to merge without complaining.
		if (!run_or_non('git', 'pull', '--no-commit', '.', $branch)) {
			$conflict = readfile($target);
			run_or_die('git', 'reset', '--hard');
		}
	};
	my $failure = $@;

	# Process undo stack (in reverse order).  By policy cleanup
	# actions should normally print a warning on failure.
	while (my $handle = pop @undo) {
		$handle->();
	}

	error("Git merge failed!\n$failure\n") if $failure;

	return $conflict;
}

sub decode_git_file ($) {
	my $file=shift;

	# git does not output utf-8 filenames, but instead
	# double-quotes them with the utf-8 characters
	# escaped as \nnn\nnn.
	if ($file =~ m/^"(.*)"$/) {
		($file=$1) =~ s/\\([0-7]{1,3})/chr(oct($1))/eg;
	}

	# strip prefix if in a subdir
	if (! defined $prefix) {
		($prefix) = run_or_die('git', 'rev-parse', '--show-prefix');
		if (! defined $prefix) {
			$prefix="";
		}
	}
	$file =~ s/^\Q$prefix\E//;

	return decode("utf8", $file);
}

sub parse_diff_tree ($) {
	# Parse the raw diff tree chunk and return the info hash.
	# See git-diff-tree(1) for the syntax.
	my $dt_ref = shift;

	# End of stream?
	return if ! @{ $dt_ref } ||
		  !defined $dt_ref->[0] || !length $dt_ref->[0];

	my %ci;
	# Header line.
	while (my $line = shift @{ $dt_ref }) {
		return if $line !~ m/^(.+) ($sha1_pattern)/;

		my $sha1 = $2;
		$ci{'sha1'} = $sha1;
		last;
	}

	# Identification lines for the commit.
	while (my $line = shift @{ $dt_ref }) {
		# Regexps are semi-stolen from gitweb.cgi.
		if ($line =~ m/^tree ([0-9a-fA-F]{40})$/) {
			$ci{'tree'} = $1;
		}
		elsif ($line =~ m/^parent ([0-9a-fA-F]{40})$/) {
			# XXX: collecting in reverse order
			push @{ $ci{'parents'} }, $1;
		}
		elsif ($line =~ m/^(author|committer) (.*) ([0-9]+) (.*)$/) {
			my ($who, $name, $epoch, $tz) =
			   ($1,   $2,    $3,     $4 );

			$ci{  $who          } = $name;
			$ci{ "${who}_epoch" } = $epoch;
			$ci{ "${who}_tz"    } = $tz;

			if ($name =~ m/^([^<]+)\s+<([^@>]+)/) {
				$ci{"${who}_name"} = $1;
				$ci{"${who}_username"} = $2;
			}
			elsif ($name =~ m/^([^<]+)\s+<>$/) {
				$ci{"${who}_username"} = $1;
			}
			else {
				$ci{"${who}_username"} = $name;
			}
		}
		elsif ($line =~ m/^$/) {
			# Trailing empty line signals next section.
			last;
		}
	}

	debug("No 'tree' seen in diff-tree output") if !defined $ci{'tree'};
	
	if (defined $ci{'parents'}) {
		$ci{'parent'} = @{ $ci{'parents'} }[0];
	}
	else {
		$ci{'parent'} = 0 x 40;
	}

	# Commit message (optional).
	while ($dt_ref->[0] =~ /^    /) {
		my $line = shift @{ $dt_ref };
		$line =~ s/^    //;
		push @{ $ci{'comment'} }, $line;
	}
	shift @{ $dt_ref } if $dt_ref->[0] =~ /^$/;

	# Modified files.
	while (my $line = shift @{ $dt_ref }) {
		if ($line =~ m{^
			(:+)       # number of parents
			([^\t]+)\t # modes, sha1, status
			(.*)       # file names
		$}xo) {
			my $num_parents = length $1;
			my @tmp = split(" ", $2);
			my ($file, $file_to) = split("\t", $3);
			my @mode_from = splice(@tmp, 0, $num_parents);
			my $mode_to = shift(@tmp);
			my @sha1_from = splice(@tmp, 0, $num_parents);
			my $sha1_to = shift(@tmp);
			my $status = shift(@tmp);

			if (length $file) {
				push @{ $ci{'details'} }, {
					'file'      => decode_git_file($file),
					'sha1_from' => $sha1_from[0],
					'sha1_to'   => $sha1_to,
					'mode_from' => $mode_from[0],
					'mode_to'   => $mode_to,
					'status'    => $status,
				};
			}
			next;
		};
		last;
	}

	return \%ci;
}

sub git_commit_info ($;$) {
	# Return an array of commit info hashes of num commits
	# starting from the given sha1sum.
	my ($sha1, $num) = @_;

	my @opts;
	push @opts, "--max-count=$num" if defined $num;

	my @raw_lines = run_or_die('git', 'log', @opts,
		'--pretty=raw', '--raw', '--abbrev=40', '--always', '-c',
		'-r', $sha1, '--', '.');

	my @ci;
	while (my $parsed = parse_diff_tree(\@raw_lines)) {
		push @ci, $parsed;
	}

	warn "Cannot parse commit info for '$sha1' commit" if !@ci;

	return wantarray ? @ci : $ci[0];
}

sub rcs_find_changes ($) {
	my $oldrev=shift;

	my @raw_lines = run_or_die('git', 'log',
		'--pretty=raw', '--raw', '--abbrev=40', '--always', '-c',
		'--no-renames', , '--reverse',
		'-r', "$oldrev..HEAD", '--', '.');

	# Due to --reverse, we see changes in chronological order.
	my %changed;
	my %deleted;
	my $nullsha = 0 x 40;
	my $newrev=$oldrev;
	while (my $ci = parse_diff_tree(\@raw_lines)) {
		$newrev=$ci->{sha1};
		foreach my $i (@{$ci->{details}}) {
			my $file=$i->{file};
			if ($i->{sha1_to} eq $nullsha) {
				delete $changed{$file};
				$deleted{$file}=1;
			}
			else {
				delete $deleted{$file};
				$changed{$file}=1;
			}
		}
	}

	return (\%changed, \%deleted, $newrev);
}

sub git_sha1_file ($) {
	my $file=shift;
	git_sha1("--", $file);
}

sub git_sha1 (@) {
	# Ignore error since a non-existing file might be given.
	my ($sha1) = run_or_non('git', 'rev-list', '--max-count=1', 'HEAD',
		'--', @_);
	if (defined $sha1) {
		($sha1) = $sha1 =~ m/($sha1_pattern)/; # sha1 is untainted now
	}
	return defined $sha1 ? $sha1 : '';
}

sub rcs_get_current_rev () {
	git_sha1();
}

sub rcs_update () {
	# Update working directory.

	if (length $config{gitorigin_branch}) {
		run_or_cry('git', 'pull', '--prune', $config{gitorigin_branch});
	}
}

sub rcs_prepedit ($) {
	# Return the commit sha1sum of the file when editing begins.
	# This will be later used in rcs_commit if a merge is required.
	my ($file) = @_;

	return git_sha1_file($file);
}

sub rcs_commit (@) {
	# Try to commit the page; returns undef on _success_ and
	# a version of the page with the rcs's conflict markers on
	# failure.
	my %params=@_;

	# Check to see if the page has been changed by someone else since
	# rcs_prepedit was called.
	my $cur    = git_sha1_file($params{file});
	my ($prev) = $params{token} =~ /^($sha1_pattern)$/; # untaint

	if (defined $cur && defined $prev && $cur ne $prev) {
		my $conflict = merge_past($prev, $params{file}, $dummy_commit_msg);
		return $conflict if defined $conflict;
	}

	return rcs_commit_helper(@_);
}

sub rcs_commit_staged (@) {
	# Commits all staged changes. Changes can be staged using rcs_add,
	# rcs_remove, and rcs_rename.
	return rcs_commit_helper(@_);
}

sub rcs_commit_helper (@) {
	my %params=@_;
	
	my %env=%ENV;

	if (defined $params{session}) {
		# Set the commit author and email based on web session info.
		my $u;
		if (defined $params{session}->param("name")) {
			$u=$params{session}->param("name");
		}
		elsif (defined $params{session}->remote_addr()) {
			$u=$params{session}->remote_addr();
		}
		if (defined $u) {
			$u=encode_utf8($u);
			$ENV{GIT_AUTHOR_NAME}=$u;
		}
		if (defined $params{session}->param("nickname")) {
			$u=encode_utf8($params{session}->param("nickname"));
			$u=~s/\s+/_/g;
			$u=~s/[^-_0-9[:alnum:]]+//g;
		}
		if (defined $u) {
			$ENV{GIT_AUTHOR_EMAIL}="$u\@web";
		}
	}

	$params{message} = IkiWiki::possibly_foolish_untaint($params{message});
	my @opts;
	if ($params{message} !~ /\S/) {
		# Force git to allow empty commit messages.
		# (If this version of git supports it.)
		my ($version)=`git --version` =~ /git version (.*)/;
		if ($version ge "1.7.8") {
			push @opts, "--allow-empty-message", "--no-edit";
		}
		if ($version ge "1.7.2") {
			push @opts, "--allow-empty-message";
		}
		elsif ($version ge "1.5.4") {
			push @opts, '--cleanup=verbatim';
		}
		else {
			$params{message}.=".";
		}
	}
	if (exists $params{file}) {
		push @opts, '--', $params{file};
	}
	# git commit returns non-zero if nothing really changed.
	# So we should ignore its exit status (hence run_or_non).
	if (run_or_non('git', 'commit', '-m', $params{message}, '-q', @opts)) {
		if (length $config{gitorigin_branch}) {
			run_or_cry('git', 'push', $config{gitorigin_branch});
		}
	}
	
	%ENV=%env;
	return undef; # success
}

sub rcs_add ($) {
	# Add file to archive.

	my ($file) = @_;

	run_or_cry('git', 'add', $file);
}

sub rcs_remove ($) {
	# Remove file from archive.

	my ($file) = @_;

	run_or_cry('git', 'rm', '-f', $file);
}

sub rcs_rename ($$) {
	my ($src, $dest) = @_;

	run_or_cry('git', 'mv', '-f', $src, $dest);
}

sub rcs_recentchanges ($) {
	# List of recent changes.

	my ($num) = @_;

	eval q{use Date::Parse};
	error($@) if $@;

	my @rets;
	foreach my $ci (git_commit_info('HEAD', $num || 1)) {
		# Skip redundant commits.
		next if ($ci->{'comment'} && @{$ci->{'comment'}}[0] eq $dummy_commit_msg);

		my ($sha1, $when) = (
			$ci->{'sha1'},
			$ci->{'author_epoch'}
		);

		my @pages;
		foreach my $detail (@{ $ci->{'details'} }) {
			my $file = $detail->{'file'};
			my $efile = uri_escape_utf8($file);

			my $diffurl = defined $config{'diffurl'} ? $config{'diffurl'} : "";
			$diffurl =~ s/\[\[file\]\]/$efile/go;
			$diffurl =~ s/\[\[sha1_parent\]\]/$ci->{'parent'}/go;
			$diffurl =~ s/\[\[sha1_from\]\]/$detail->{'sha1_from'}/go;
			$diffurl =~ s/\[\[sha1_to\]\]/$detail->{'sha1_to'}/go;
			$diffurl =~ s/\[\[sha1_commit\]\]/$sha1/go;

			push @pages, {
				page => pagename($file),
				diffurl => $diffurl,
			};
		}

		my @messages;
		my $pastblank=0;
		foreach my $line (@{$ci->{'comment'}}) {
			$pastblank=1 if $line eq '';
			next if $pastblank && $line=~m/^ *(signed[ \-]off[ \-]by[ :]|acked[ \-]by[ :]|cc[ :])/i;
			push @messages, { line => $line };
		}

		my $user=$ci->{'author_username'};
		my $web_commit = ($ci->{'author'} =~ /\@web>/);
		my $nickname;

		# Set nickname only if a non-url author_username is available,
		# and author_name is an url.
		if ($user !~ /:\/\// && defined $ci->{'author_name'} &&
		    $ci->{'author_name'} =~ /:\/\//) {
			$nickname=$user;
			$user=$ci->{'author_name'};
		}

		# compatability code for old web commit messages
		if (! $web_commit &&
		      defined $messages[0] &&
		      $messages[0]->{line} =~ m/$config{web_commit_regexp}/) {
			$user = defined $2 ? "$2" : "$3";
			$messages[0]->{line} = $4;
		 	$web_commit=1;
		}

		push @rets, {
			rev        => $sha1,
			user       => $user,
			nickname   => $nickname,
			committype => $web_commit ? "web" : "git",
			when       => $when,
			message    => [@messages],
			pages      => [@pages],
		} if @pages;

		last if @rets >= $num;
	}

	return @rets;
}

sub rcs_diff ($;$) {
	my $rev=shift;
	my $maxlines=shift;
	my ($sha1) = $rev =~ /^($sha1_pattern)$/; # untaint
	my @lines;
	my $addlines=sub {
		my $line=shift;
		return if defined $maxlines && @lines == $maxlines;
		push @lines, $line."\n"
			if (@lines || $line=~/^diff --git/);
		return 1;
	};
	safe_git(undef, $addlines, "git", "show", $sha1);
	if (wantarray) {
		return @lines;
	}
	else {
		return join("", @lines);
	}
}

{
my %time_cache;

sub findtimes ($$) {
	my $file=shift;
	my $id=shift; # 0 = mtime ; 1 = ctime

	if (! keys %time_cache) {
		my $date;
		foreach my $line (run_or_die('git', 'log',
				'--pretty=format:%at',
				'--name-only', '--relative')) {
			if (! defined $date && $line =~ /^(\d+)$/) {
				$date=$line;
			}
			elsif (! length $line) {
				$date=undef;
			}
			else {
				my $f=decode_git_file($line);

				if (! $time_cache{$f}) {
					$time_cache{$f}[0]=$date; # mtime
				}
				$time_cache{$f}[1]=$date; # ctime
			}
		}
	}

	return exists $time_cache{$file} ? $time_cache{$file}[$id] : 0;
}

}

sub rcs_getctime ($) {
	my $file=shift;

	return findtimes($file, 1);
}

sub rcs_getmtime ($) {
	my $file=shift;

	return findtimes($file, 0);
}

{
my $ret;
sub git_find_root {
	# The wiki may not be the only thing in the git repo.
	# Determine if it is in a subdirectory by examining the srcdir,
	# and its parents, looking for the .git directory.

	return @$ret if defined $ret;
	
	my $subdir="";
	my $dir=$config{srcdir};
	while (! -d "$dir/.git") {
		$subdir=IkiWiki::basename($dir)."/".$subdir;
		$dir=IkiWiki::dirname($dir);
		if (! length $dir) {
			error("cannot determine root of git repo");
		}
	}

	$ret=[$subdir, $dir];
	return @$ret;
}

}

sub git_parse_changes {
	my $reverted = shift;
	my @changes = @_;

	my ($subdir, $rootdir) = git_find_root();
	my @rets;
	foreach my $ci (@changes) {
		foreach my $detail (@{ $ci->{'details'} }) {
			my $file = $detail->{'file'};

			# check that all changed files are in the subdir
			if (length $subdir &&
			    ! ($file =~ s/^\Q$subdir\E//)) {
				error sprintf(gettext("you are not allowed to change %s"), $file);
			}

			my ($action, $mode, $path);
			if ($detail->{'status'} =~ /^[M]+\d*$/) {
				$action="change";
				$mode=$detail->{'mode_to'};
			}
			elsif ($detail->{'status'} =~ /^[AM]+\d*$/) {
				$action= $reverted ? "remove" : "add";
				$mode=$detail->{'mode_to'};
			}
			elsif ($detail->{'status'} =~ /^[DAM]+\d*/) {
				$action= $reverted ? "add" : "remove";
				$mode=$detail->{'mode_from'};
			}
			else {
				error "unknown status ".$detail->{'status'};
			}

			# test that the file mode is ok
			if ($mode !~ /^100[64][64][64]$/) {
				error sprintf(gettext("you cannot act on a file with mode %s"), $mode);
			}
			if ($action eq "change") {
				if ($detail->{'mode_from'} ne $detail->{'mode_to'}) {
					error gettext("you are not allowed to change file modes");
				}
			}

			# extract attachment to temp file
			if (($action eq 'add' || $action eq 'change') &&
			    ! pagetype($file)) {
				eval q{use File::Temp};
				die $@ if $@;
				my $fh;
				($fh, $path)=File::Temp::tempfile(undef, UNLINK => 1);
				my $cmd = "cd $git_dir && ".
				          "git show $detail->{sha1_to} > '$path'";
				if (system($cmd) != 0) {
					error("failed writing temp file '$path'.");
				}
			}

			push @rets, {
				file => $file,
				action => $action,
				path => $path,
			};
		}
	}

	return @rets;
}

sub rcs_receive () {
	my @rets;
	while (<>) {
		chomp;
		my ($oldrev, $newrev, $refname) = split(' ', $_, 3);

		# only allow changes to gitmaster_branch
		if ($refname !~ /^refs\/heads\/\Q$config{gitmaster_branch}\E$/) {
			error sprintf(gettext("you are not allowed to change %s"), $refname);
		}

		# Avoid chdir when running git here, because the changes
		# are in the master git repo, not the srcdir repo.
		# (Also, if a subdir is involved, we don't want to chdir to
		# it and only see changes in it.)
		# The pre-receive hook already puts us in the right place.
		in_git_dir(".", sub {
			push @rets, git_parse_changes(0, git_commit_info($oldrev."..".$newrev));
		});
	}

	return reverse @rets;
}

sub rcs_preprevert ($) {
	my $rev=shift;
	my ($sha1) = $rev =~ /^($sha1_pattern)$/; # untaint

	# Examine changes from root of git repo, not from any subdir,
	# in order to see all changes.
	my ($subdir, $rootdir) = git_find_root();
	in_git_dir($rootdir, sub {
		my @commits=git_commit_info($sha1, 1);
	
		if (! @commits) {
			error "unknown commit"; # just in case
		}

		# git revert will fail on merge commits. Add a nice message.
		if (exists $commits[0]->{parents} &&
		    @{$commits[0]->{parents}} > 1) {
			error gettext("you are not allowed to revert a merge");
		}

		git_parse_changes(1, @commits);
	});
}

sub rcs_revert ($) {
	# Try to revert the given rev; returns undef on _success_.
	my $rev = shift;
	my ($sha1) = $rev =~ /^($sha1_pattern)$/; # untaint

	if (run_or_non('git', 'revert', '--no-commit', $sha1)) {
		return undef;
	}
	else {
		run_or_die('git', 'reset', '--hard');
		return sprintf(gettext("Failed to revert commit %s"), $sha1);
	}
}

1
