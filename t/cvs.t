#!/usr/bin/perl
use warnings;
use strict;
use Test::More;
use IkiWiki;

my $dir;

sub _determine_test_plan {
	my $cvs=`which cvs`; chomp $cvs;
	my $cvsps=`which cvsps`; chomp $cvsps;
	return (skip_all => 'cvs or cvsps not available')
		unless -x $cvs && -x $cvsps;

	foreach my $module ('File::ReadBackwards', 'File::MimeInfo') {
		eval qq{use $module};
		if ($@) {
			return (skip_all => "$module not available");
		}
	}

	return (tests => 11);
}

sub _startup {
	_mktempdir();
	_generate_minimal_config();
	_create_test_repo();
}

sub _shutdown {
	system "rm -rf $dir";
}

sub _mktempdir {
	$dir="/tmp/ikiwiki-test-cvs.$$";
	if (! mkdir($dir)) {
		die $@;
	}
}

sub _generate_minimal_config {
	%config=IkiWiki::defaultconfig();
	$config{rcs} = "cvs";
	$config{srcdir} = "$dir/src";
	$config{cvsrepo} = "$dir/repo";
	$config{cvspath} = "ikiwiki";
	IkiWiki::loadplugins();
	IkiWiki::checkconfig();
}

sub _create_test_repo {
	my $cvsrepo = "$dir/repo";

	system "cvs -d $cvsrepo init >/dev/null";
	system "mkdir $dir/ikiwiki >/dev/null";
	system "cd $dir/ikiwiki && cvs -d $cvsrepo import -m import ikiwiki VENDOR RELEASE >/dev/null";
	system "rm -rf $dir/ikiwiki >/dev/null";
	system "cvs -d $cvsrepo co -d $config{srcdir} ikiwiki >/dev/null";
}

sub test_web_commit {
	my $test1 = readfile("t/test1.mdwn");
	writefile('test1.mdwn', $config{srcdir}, $test1);
	IkiWiki::rcs_add("test1.mdwn");
	IkiWiki::rcs_commit(
		file => "test1.mdwn",
		message => "Added the first page",
		token => "moo",
	);

	my @changes = IkiWiki::rcs_recentchanges(3);

	is($#changes, 0);
	is($changes[0]{message}[0]{"line"}, "Added the first page");
	is($changes[0]{pages}[0]{"page"}, "test1");
}

sub test_manual_commit {
	my $message = "Added the second page";

	my $test2 = readfile("t/test2.mdwn");
	writefile('test2.mdwn', $config{srcdir}, $test2);
	system "cd $config{srcdir} && cvs add test2.mdwn >/dev/null 2>&1";
	system "cd $config{srcdir} && cvs commit -m \"$message\" test2.mdwn >/dev/null";

	my @changes = IkiWiki::rcs_recentchanges(3);
	is($#changes, 1);
	is($changes[0]{message}[0]{"line"}, $message);
	is($changes[0]{pages}[0]{"page"}, "test2");
	is($changes[1]{pages}[0]{"page"}, "test1");

	# extra slashes in the path shouldn't break things
	$config{cvspath} = "/ikiwiki//";
	IkiWiki::checkconfig();
	@changes = IkiWiki::rcs_recentchanges(3);
	is($#changes, 1);
	is($changes[0]{message}[0]{"line"}, $message);
	is($changes[0]{pages}[0]{"page"}, "test2");
	is($changes[1]{pages}[0]{"page"}, "test1");
}

plan(_determine_test_plan());
_startup();
test_web_commit();
test_manual_commit();
_shutdown();
