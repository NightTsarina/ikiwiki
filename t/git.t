#!/usr/bin/perl
use warnings;
use strict;

my $dir;
BEGIN {
	$dir="/tmp/ikiwiki-test-git.$$";
	my $git=`which git`;
	chomp $git;
	if (! -x $git) {
		eval q{
			use Test::More skip_all => "git not available"
		}
	}
	if (! mkdir($dir)) {
		die $@;
	}
}
use Test::More tests => 18;

BEGIN { use_ok("IkiWiki"); }

%config=IkiWiki::defaultconfig();
$config{rcs} = "git";
$config{srcdir} = "$dir/src";
IkiWiki::loadplugins();
IkiWiki::checkconfig();

ok (mkdir($config{srcdir}));
is (system("./ikiwiki-makerepo git $config{srcdir} $dir/repo"), 0);

my @changes;
@changes = IkiWiki::rcs_recentchanges(3);

is($#changes, 0); # counts for dummy commit during repo creation
# ikiwiki-makerepo's first commit is setting up the .gitignore
is($changes[0]{message}[0]{"line"}, "initial commit");
is($changes[0]{pages}[0]{"page"}, ".gitignore");

# Web commit
my $test1 = readfile("t/test1.mdwn");
writefile('test1.mdwn', $config{srcdir}, $test1);
IkiWiki::rcs_add("test1.mdwn");
IkiWiki::rcs_commit(
	file => "test1.mdwn",
	message => "Added the first page",
	token => "moo",
);

@changes = IkiWiki::rcs_recentchanges(3);

is($#changes, 1);
is($changes[0]{message}[0]{"line"}, "Added the first page");
is($changes[0]{pages}[0]{"page"}, "test1");
	
# Manual commit
my $message = "Added the second page";

my $test2 = readfile("t/test2.mdwn");
writefile('test2.mdwn', $config{srcdir}, $test2);
system "cd $config{srcdir}; git add test2.mdwn >/dev/null 2>&1";
system "cd $config{srcdir}; git commit -m \"$message\" test2.mdwn >/dev/null 2>&1";
system "cd $config{srcdir}; git push origin >/dev/null 2>&1";

@changes = IkiWiki::rcs_recentchanges(3);

is($#changes, 2);
is($changes[0]{message}[0]{"line"}, $message);
is($changes[0]{pages}[0]{"page"}, "test2");

is($changes[1]{pages}[0]{"page"}, "test1");

# Renaming

writefile('test3.mdwn', $config{srcdir}, $test1);
IkiWiki::rcs_add("test3.mdwn");
IkiWiki::rcs_rename("test3.mdwn", "test4.mdwn");
IkiWiki::rcs_commit_staged(message => "Added the 4th page");

@changes = IkiWiki::rcs_recentchanges(4);

is($#changes, 3);
is($changes[0]{pages}[0]{"page"}, "test4");

ok(mkdir($config{srcdir}."/newdir"));
IkiWiki::rcs_rename("test4.mdwn", "newdir/test5.mdwn");
IkiWiki::rcs_commit_staged(message => "Added the 5th page");

@changes = IkiWiki::rcs_recentchanges(4);

is($#changes, 3);
is($changes[0]{pages}[0]{"page"}, "newdir/test5");

IkiWiki::rcs_remove("newdir/test5.mdwn");
IkiWiki::rcs_commit_staged(message => "Remove the 5th page");

system "rm -rf $dir";
