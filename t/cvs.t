#!/usr/bin/perl
use warnings;
use strict;
my $dir;
BEGIN {
	$dir="/tmp/ikiwiki-test-cvs.$$";
	my $cvs=`which cvs`;
	chomp $cvs;
	my $cvsps=`which cvsps`;
	chomp $cvsps;
	if (! -x $cvs || ! -x $cvsps) {
		eval q{
			use Test::More skip_all => "cvs or cvsps not available"
		}
	}
	if (! mkdir($dir)) {
		die $@;
	}
	foreach my $module ('File::ReadBackwards', 'File::MimeInfo') {
		eval qq{use $module};
		if ($@) {
			eval qq{
				use Test::More skip_all => "$module not available"
			}
		}
	}
}
use Test::More tests => 12;

BEGIN { use_ok("IkiWiki"); }

sub _startup {
	_generate_minimal_config();
	_create_test_repo();
}

sub _shutdown {
	system "rm -rf $dir";
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
		files => "test1.mdwn",
		message => "Added the first page",
		token => "moo"
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

_startup();
test_web_commit();
test_manual_commit();
_shutdown();
