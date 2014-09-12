#!/usr/bin/perl
use warnings;
use strict;
my $dir;
BEGIN {
	$dir = "/tmp/ikiwiki-test-bzr.$$";
	my $bzr=`which bzr`;
	chomp $bzr;
	if (! -x $bzr) {
		eval q{
			use Test::More skip_all => "bzr not available"
		}
	}
	if (! mkdir($dir)) {
		die $@;
	}
}
use Test::More tests => 17;

BEGIN { use_ok("IkiWiki"); }

%config=IkiWiki::defaultconfig();
$config{rcs} = "bzr";
$config{srcdir} = "$dir/repo";
IkiWiki::loadplugins();
IkiWiki::checkconfig();

# XXX
# This is a workaround for bzr's new requirement that bzr whoami be run
# before committing. This makes the test suite work with an unconfigured
# bzr, but ignores the need to have a properly configured bzr before
# using ikiwiki with bzr.
$ENV{HOME}=$dir;
system 'bzr whoami test@example.com';

system "bzr init $config{srcdir}";

use CGI::Session;
my $session=CGI::Session->new;
$session->param("name", "Joe User");

# Web commit
my $test1 = readfile("t/test1.mdwn");
writefile('test1.mdwn', $config{srcdir}, $test1);
IkiWiki::rcs_add("test1.mdwn");
IkiWiki::rcs_commit(
	file => "test1.mdwn",
	message => "Added the first page",
	token => "moo",
	session => $session);

my @changes;
@changes = IkiWiki::rcs_recentchanges(3);

is($#changes, 0);
is($changes[0]{message}[0]{"line"}, "Added the first page");
is($changes[0]{pages}[0]{"page"}, "test1");
is($changes[0]{user}, "Joe User");
	
# Manual commit
my $username = "Foo Bar";
my $user = "$username <foo.bar\@example.com>";
my $message = "Added the second page";

my $test2 = readfile("t/test2.mdwn");
writefile('test2.mdwn', $config{srcdir}, $test2);
system "bzr add --quiet $config{srcdir}/test2.mdwn";
system "bzr commit --quiet --author \"$user\" -m \"$message\" $config{srcdir}";
	
@changes = IkiWiki::rcs_recentchanges(3);

is($#changes, 1);
is($changes[0]{message}[0]{"line"}, $message);
is($changes[0]{user}, $username);
is($changes[0]{pages}[0]{"page"}, "test2");

is($changes[1]{pages}[0]{"page"}, "test1");

my $ctime = IkiWiki::rcs_getctime("test2.mdwn");
ok($ctime >= time() - 20);

my $mtime = IkiWiki::rcs_getmtime("test2.mdwn");
ok($mtime >= time() - 20);

writefile('test3.mdwn', $config{srcdir}, $test1);
IkiWiki::rcs_add("test3.mdwn");
IkiWiki::rcs_rename("test3.mdwn", "test4.mdwn");
IkiWiki::rcs_commit_staged(
	message => "Added the 4th page",
	session => $session,
);

@changes = IkiWiki::rcs_recentchanges(4);

is($#changes, 2);
is($changes[0]{pages}[0]{"page"}, "test4");

ok(mkdir($config{srcdir}."/newdir"));
IkiWiki::rcs_rename("test4.mdwn", "newdir/test5.mdwn");
IkiWiki::rcs_commit_staged(
	message => "Added the 5th page",
	session => $session,
);

@changes = IkiWiki::rcs_recentchanges(4);

is($#changes, 3);
is($changes[0]{pages}[0]{"page"}, "newdir/test5");

IkiWiki::rcs_remove("newdir/test5.mdwn");
IkiWiki::rcs_commit_staged(
	message => "Remove the 5th page",
	session => $session,
);

system "rm -rf $dir";
