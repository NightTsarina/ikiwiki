#!/usr/bin/perl
package IkiWiki::Plugin::svn;

use warnings;
use strict;
use IkiWiki;
use POSIX qw(setlocale LC_CTYPE);
use URI::Escape q{uri_escape_utf8};

sub import {
	hook(type => "checkconfig", id => "svn", call => \&checkconfig);
	hook(type => "getsetup", id => "svn", call => \&getsetup);
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
	if (! defined $config{svnpath}) {
		$config{svnpath}="trunk";
	}
	if (exists $config{svnpath}) {
		# code depends on the path not having extraneous slashes
		$config{svnpath}=~tr#/#/#s;
		$config{svnpath}=~s/\/$//;
		$config{svnpath}=~s/^\///;
	}
	if (defined $config{svn_wrapper} && length $config{svn_wrapper}) {
		push @{$config{wrappers}}, {
			wrapper => $config{svn_wrapper},
			wrappermode => (defined $config{svn_wrappermode} ? $config{svn_wrappermode} : "04755"),
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
		svnrepo => {
			type => "string",
			example => "/svn/wiki",
			description => "subversion repository location",
			safe => 0, # path
			rebuild => 0,
		},
		svnpath => {
			type => "string",
			example => "trunk",
			description => "path inside repository where the wiki is located",
			safe => 0, # paranoia
			rebuild => 0,
		},
		svn_wrapper => {
			type => "string",
			example => "/svn/wikirepo/hooks/post-commit",
			description => "svn post-commit hook to generate",
			safe => 0, # file
			rebuild => 0,
		},
		svn_wrappermode => {
			type => "string",
			example => '04755',
			description => "mode for svn_wrapper (can safely be made suid)",
			safe => 0,
			rebuild => 0,
		},
		historyurl => {
			type => "string",
			example => "http://svn.example.org/trunk/[[file]]",
			description => "viewvc url to show file history ([[file]] substituted)",
			safe => 1,
			rebuild => 1,
		},
		diffurl => {
			type => "string",
			example => "http://svn.example.org/trunk/[[file]]?root=wiki&amp;r1=[[r1]]&amp;r2=[[r2]]",
			description => "viewvc url to show a diff ([[file]], [[r1]], and [[r2]] substituted)",
			safe => 1,
			rebuild => 1,
		},
}

# svn needs LC_CTYPE set to a UTF-8 locale, so try to find one. Any will do.
sub find_lc_ctype() {
	my $current = setlocale(LC_CTYPE());
	return $current if $current =~ m/UTF-?8$/i;

	# Make some obvious attempts to avoid calling `locale -a`
	foreach my $locale ("$current.UTF-8", "en_US.UTF-8", "en_GB.UTF-8") {
		return $locale if setlocale(LC_CTYPE(), $locale);
	}

	# Try to get all available locales and pick the first UTF-8 one found.
	if (my @locale = grep(/UTF-?8$/i, `locale -a`)) {
		chomp @locale;
		return $locale[0] if setlocale(LC_CTYPE(), $locale[0]);
	}

	# fallback to the current locale
	return $current;
}
$ENV{LC_CTYPE} = $ENV{LC_CTYPE} || find_lc_ctype();

sub svn_info ($$) {
	my $field=shift;
	my $file=shift;

	my $info=`LANG=C svn info $file`;
	my ($ret)=$info=~/^$field: (.*)$/m;
	return $ret;
}

sub rcs_update () {
	if (system("svn", "update", "--quiet", $config{srcdir}) != 0) {
		warn("svn update failed\n");
	}
}

sub rcs_prepedit ($) {
	# Prepares to edit a file under revision control. Returns a token
	# that must be passed into rcs_commit when the file is ready
	# for committing.
	# The file is relative to the srcdir.
	my $file=shift;
	
	# For subversion, return the revision of the file when
	# editing begins.
	my $rev=svn_info("Revision", "$config{srcdir}/$file");
	return defined $rev ? $rev : "";
}

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

sub rcs_commit (@) {
	# Tries to commit the page; returns undef on _success_ and
	# a version of the page with the rcs's conflict markers on failure.
	# The file is relative to the srcdir.
	my %params=@_;

	# Check to see if the page has been changed by someone
	# else since rcs_prepedit was called.
	my ($oldrev)=$params{token}=~/^([0-9]+)$/; # untaint
	my $rev=svn_info("Revision", "$config{srcdir}/$params{file}");
	if (defined $rev && defined $oldrev && $rev != $oldrev) {
		# Merge their changes into the file that we've
		# changed.
		if (system("svn", "merge", "--quiet", "-r$oldrev:$rev",
		           "$config{srcdir}/$params{file}", "$config{srcdir}/$params{file}") != 0) {
			warn("svn merge -r$oldrev:$rev failed\n");
		}
	}

	if (system("svn", "commit", "--quiet", 
	           "--encoding", "UTF-8", "-m",
	           IkiWiki::possibly_foolish_untaint(commitmessage(%params)),
		   $config{srcdir}) != 0) {
		my $conflict=readfile("$config{srcdir}/$params{file}");
		if (system("svn", "revert", "--quiet", "$config{srcdir}/$params{file}") != 0) {
			warn("svn revert failed\n");
		}
		return $conflict;
	}

	return undef # success
}

sub rcs_commit_staged (@) {
	# Commits all staged changes. Changes can be staged using rcs_add,
	# rcs_remove, and rcs_rename.
	my %params=@_;
	
	if (system("svn", "commit", "--quiet",
	           "--encoding", "UTF-8", "-m",
	           IkiWiki::possibly_foolish_untaint(commitmessage(%params)),
		   $config{srcdir}) != 0) {
		warn("svn commit failed\n");
		return 1; # failure	
	}
	return undef # success
}

sub rcs_add ($) {
	# filename is relative to the root of the srcdir
	my $file=shift;

	if (system("svn", "add", "--parents", "--quiet", "$config{srcdir}/$file") != 0) {
		warn("svn add failed\n");
	}
}

sub rcs_remove ($) {
	# filename is relative to the root of the srcdir
	my $file=shift;

	if (system("svn", "rm", "--force", "--quiet", "$config{srcdir}/$file") != 0) {
		warn("svn rm failed\n");
	}
}

sub rcs_rename ($$) {
	# filenames relative to the root of the srcdir
	my ($src, $dest)=@_;
	
	if (system("svn", "mv", "--parents", "--force", "--quiet", 
	    "$config{srcdir}/$src", "$config{srcdir}/$dest") != 0) {
		warn("svn rename failed\n");
	}
}

sub rcs_recentchanges ($) {
	my $num=shift;
	my @ret;
	
	eval q{
		use Date::Parse;
		use XML::SAX;
		use XML::Simple;
	};
	error($@) if $@;

	# avoid using XML::SAX::PurePerl, it's buggy with UTF-8 data
	my @parsers = map { ${$_}{Name} } @{XML::SAX->parsers()};
	do {
		$XML::Simple::PREFERRED_PARSER = pop @parsers;
	} until $XML::Simple::PREFERRED_PARSER ne 'XML::SAX::PurePerl';

	# --limit is only supported on Subversion 1.2.0+
	my $svn_version=`svn --version -q`;
	my $svn_limit='';
	$svn_limit="--limit $num"
		if $svn_version =~ /\d\.(\d)\.\d/ && $1 >= 2;

	my $svn_url=svn_info("URL", $config{srcdir});
	my $xml = XMLin(scalar `svn $svn_limit --xml -v log '$svn_url'`,
		ForceArray => [ 'logentry', 'path' ],
		GroupTags => { paths => 'path' },
		KeyAttr => { path => 'content' },
	);
	foreach my $logentry (@{$xml->{logentry}}) {
		my (@pages, @message);

		my $rev = $logentry->{revision};
		my $user = $logentry->{author};

		my $when=str2time($logentry->{date}, 'UTC');

		foreach my $msgline (split(/\n/, $logentry->{msg})) {
			push @message, { line => $msgline };
		}

		my $committype="web";
		if (defined $message[0] &&
		    $message[0]->{line}=~/$config{web_commit_regexp}/) {
			$user=defined $2 ? "$2" : "$3";
			$message[0]->{line}=$4;
		}
		else {
			$committype="svn";
		}

		foreach my $file (keys %{$logentry->{paths}}) {
			if (length $config{svnpath}) {
				next unless $file=~/^\/\Q$config{svnpath}\E\/([^ ]+)(?:$|\s)/;
				$file=$1;
			}

			my $diffurl=defined $config{diffurl} ? $config{diffurl} : "";
			my $efile = uri_escape_utf8($file);
			$diffurl=~s/\[\[file\]\]/$efile/g;
			$diffurl=~s/\[\[r1\]\]/$rev - 1/eg;
			$diffurl=~s/\[\[r2\]\]/$rev/g;

			push @pages, {
				page => pagename($file),
				diffurl => $diffurl,
			} if length $file;
		}
		push @ret, {
			rev => $rev,
			user => $user,
			committype => $committype,
			when => $when,
			message => [@message],
			pages => [@pages],
		} if @pages;
		return @ret if @ret >= $num;
	}

	return @ret;
}

sub rcs_diff ($;$) {
	my $rev=IkiWiki::possibly_foolish_untaint(int(shift));
	my $maxlines=shift;
	return `svnlook diff $config{svnrepo} -r$rev --no-diff-deleted`;
}

{

my ($lastfile, $lastmtime, $lastctime);

sub findtimes ($) {
	my $file=shift;

	if (defined $lastfile && $lastfile eq $file) {
		return $lastmtime, $lastctime;
	}
	$lastfile=$file;

	my $svn_log_infoline=qr/^r\d+\s+\|\s+[^\s]+\s+\|\s+(\d+-\d+-\d+\s+\d+:\d+:\d+\s+[-+]?\d+).*/;
		
	my $child = open(SVNLOG, "-|");
	if (! $child) {
		exec("svn", "log", "$config{srcdir}/$file") || error("svn log failed to run");
	}

	my ($cdate, $mdate);
	while (<SVNLOG>) {
		if (/$svn_log_infoline/) {
			$cdate=$1;
			$mdate=$1 unless defined $mdate;
	    	}
	}
	close SVNLOG || error "svn log exited $?";

	if (! defined $cdate) {
		error "failed to parse svn log for $file";
	}
		
	eval q{use Date::Parse};
	error($@) if $@;
	
	$lastctime=str2time($cdate);
	$lastmtime=str2time($mdate);
	return $lastmtime, $lastctime;
}

}

sub rcs_getctime ($) {
	my $file=shift;

	return (findtimes($file))[1];
}

sub rcs_getmtime ($) {
	my $file=shift;

	return (findtimes($file))[0];
}

1
