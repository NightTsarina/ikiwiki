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
	if (! -x $cvs || ! -x $cvsps || ! mkdir($dir)) {
		eval q{
			use Test::More skip_all => "cvs or cvsps not available or could not make test dir"
		}
	}
}
use Test::More tests => 12;

BEGIN { use_ok("IkiWiki"); }

%config=IkiWiki::defaultconfig();
$config{rcs} = "cvs";
$config{srcdir} = "$dir/src";
$config{cvsrepo} = "$dir/repo";
$config{cvspath} = "ikiwiki";
IkiWiki::loadplugins();
IkiWiki::checkconfig();

my $cvsrepo = "$dir/repo";

system "cvs -d $cvsrepo init >/dev/null";
system "mkdir $dir/ikiwiki >/dev/null";
system "cd $dir/ikiwiki && cvs -d $cvsrepo import -m import ikiwiki VENDOR RELEASE >/dev/null";
system "rm -rf $dir/ikiwiki >/dev/null";
system "cvs -d $cvsrepo co -d $config{srcdir} ikiwiki >/dev/null";

# Web commit
my $test1 = readfile("t/test1.mdwn");
writefile('test1.mdwn', $config{srcdir}, $test1);
IkiWiki::rcs_add("test1.mdwn");
IkiWiki::rcs_commit("test1.mdwn", "Added the first page", "moo");

my @changes;
@changes = IkiWiki::rcs_recentchanges(3);

is($#changes, 0);
is($changes[0]{message}[0]{"line"}, "Added the first page");
is($changes[0]{pages}[0]{"page"}, "test1");

# Manual commit
my $message = "Added the second page";

my $test2 = readfile("t/test2.mdwn");
writefile('test2.mdwn', $config{srcdir}, $test2);
system "cd $config{srcdir} && cvs add test2.mdwn >/dev/null 2>&1";
system "cd $config{srcdir} && cvs commit -m \"$message\" test2.mdwn >/dev/null";

@changes = IkiWiki::rcs_recentchanges(3);
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

system "rm -rf $dir";
