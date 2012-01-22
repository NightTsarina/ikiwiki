#!/usr/bin/perl
use warnings;
use strict;
use Test::More;
use IkiWiki;

my %ideal_test_plan = (tests => 8);
my $dir;

sub _determine_test_plan {
	my $cvs = `which cvs`; chomp $cvs;
	my $cvsps = `which cvsps`; chomp $cvsps;
	return (skip_all => 'cvs or cvsps not available')
		unless -x $cvs && -x $cvsps;

	foreach my $module (qw(File::ReadBackwards File::MimeInfo)) {
		eval qq{use $module};
		if ($@) {
			return (skip_all => "$module not available");
		}
	}

	$dir = "/tmp/ikiwiki-test-cvs.$$";
	return (skip_all => "can't create $dir: $!")
		unless mkdir($dir);

	return %ideal_test_plan;
}

sub _startup {
	_generate_minimal_config();
	_create_test_repo();
}

sub _shutdown {
	system "rm -rf $dir";
}

sub _generate_minimal_config {
	%config = IkiWiki::defaultconfig();
	$config{rcs} = "cvs";
	$config{srcdir} = "$dir/src";
	$config{cvsrepo} = "$dir/repo";
	$config{cvspath} = "ikiwiki";
	IkiWiki::loadplugins();
	IkiWiki::checkconfig();
}

sub _create_test_repo {
	my $cvs = "cvs -d $config{cvsrepo}";
	my $dn = ">/dev/null";
	system "$cvs init $dn";
	system "mkdir $dir/$config{cvspath} $dn";
	system "cd $dir/$config{cvspath} && "
		. "$cvs import -m import $config{cvspath} VENDOR RELEASE $dn";
	system "rm -rf $dir/$config{cvspath} $dn";
	system "$cvs co -d $config{srcdir} $config{cvspath} $dn";
}

sub test_web_add_and_commit {
	my $message = "Added the first page";
	writefile('test1.mdwn', $config{srcdir}, readfile("t/test1.mdwn"));
	IkiWiki::rcs_add("test1.mdwn");
	IkiWiki::rcs_commit(
		file => "test1.mdwn",
		message => $message,
		token => "moo",
	);

	my @changes = IkiWiki::rcs_recentchanges(3);
	is(
		$#changes,
		0,
		q{1 total commit},
	);
	is(
		$changes[0]{message}[0]{"line"},
		$message,
		q{first line of most recent commit message matches},
	);
	is(
		$changes[0]{pages}[0]{"page"},
		"test1",
		q{first pagename from most recent commit matches},
	);
}

sub test_manual_add_and_commit {
	my $message = "Added the second page";
	writefile('test2.mdwn', $config{srcdir}, readfile("t/test2.mdwn"));
	system "cd $config{srcdir}"
		. " && cvs add test2.mdwn >/dev/null 2>&1";
	system "cd $config{srcdir}"
		. " && cvs commit -m \"$message\" test2.mdwn >/dev/null";

	my @changes = IkiWiki::rcs_recentchanges(3);
	is(
		$#changes,
		1,
		q{2 total commits},
	);
	is(
		$changes[0]{message}[0]{"line"},
		$message,
		q{first line of most recent commit message matches},
	);
	is(
		$changes[0]{pages}[0]{"page"},
		"test2",
		q{first pagename from most recent commit matches},
	);
	is(
		$changes[1]{pages}[0]{"page"},
		"test1",
		q{first pagename from second-most-recent commit matches},
	);
}

sub test_extra_path_slashes {
	my $initial_cvspath = $config{cvspath};
	$config{cvspath} = "/ikiwiki//";
	IkiWiki::checkconfig();
	is(
		$config{cvspath},
		$initial_cvspath,
		q{rcs_recentchanges assumes checkconfig sanitizes cvspath},
	);
}

plan(_determine_test_plan());
_startup();
test_web_add_and_commit();
test_manual_add_and_commit();
test_extra_path_slashes();
_shutdown();
