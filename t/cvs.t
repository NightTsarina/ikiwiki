#!/usr/bin/perl
use warnings;
use strict;
use Test::More; my $total_tests = 40;
use IkiWiki;

my $default_test_methods = '^test_*';
my @required_programs = qw(
	cvs
	cvsps
);
my @required_modules = qw(
	File::chdir
	File::MimeInfo
	Date::Parse
	File::Temp
	File::ReadBackwards
);
my $dir = "/tmp/ikiwiki-test-cvs.$$";

# TESTS FOR GENERAL META-BEHAVIOR

sub test_web_comments {
	# how much of the web-edit workflow are we actually testing?
	# because we want to test comments:
	# - when the first comment for page.mdwn is added, and page/ is
	#   created to hold the comment, page/ isn't added to CVS control,
	#   so the comment isn't either
	# - side effect for moderated comments: after approval they
	#   show up normally AND are still pending, too
	# - comments.pm treats rcs_commit_staged() as returning conflicts?
}

sub test_chdir_magic {
	# cvs.pm operations are always occurring inside $config{srcdir}
	# other ikiwiki operations are occurring wherever, and are unaffected
	# when are we bothering with "local $CWD" and when aren't we?
}

sub test_cvs_info {
	# inspect "Repository revision" (used in code)
	# inspect "Sticky Options" (used in tests to verify existence of "-kb")
}

sub test_cvs_run_cvs {
	# extract the stdout-redirect thing
	# - prove that it silences stdout
	# - prove that stderr comes through just fine
	# prove that when cvs exits nonzero (fail), function exits false
	# prove that when cvs exits zero (success), function exits true
	# always pass -f, just in case
	# steal from git.pm: safe_git(), run_or_{die,cry,non}
	# - open() instead of system()
	# always call cvs_run_cvs(), don't ever run 'cvs' directly
}

sub test_cvs_run_cvsps {
	# parameterize command like run_cvs()
	# expose config vars for e.g. "--cvs-direct -z 30"
	# always pass -x (unless proven otherwise)
	# always pass -b HEAD (configurable like gitmaster_branch?)
}

sub test_cvs_parse_cvsps {
	# extract method from rcs_recentchanges
	# document expected changeset format
	# document expected changeset delimiter
	# try: cvsps -q -x -p && ls | sort -rn | head -100
	# - benchmark against current impl (that uses File::ReadBackwards)
}

sub test_cvs_parse_log_accum {
	# add new, preferred method for rcs_recentchanges to use
	# teach log_accum to record commits (into transient?)
	# script cvsps to bootstrap (or replace?) commit history
	# teach ikiwiki-makerepo to set up log_accum and commit_prep
	# why are NetBSD commit mails unreliable?
	# - is it working for CVS commits and failing for web commits?
}

sub test_cvs_is_controlling {
	# with no args:
	# - if srcdir is in CVS, return true
	# - else, return false
	# with a dir arg:
	# - if dir is in CVS, return true
	# - else, return false
	# with a file arg:
	# - is there anything that wants the answer? if so, answer
	# - else, die
}


# TESTS FOR GENERAL PLUGIN API CALLS

sub test_checkconfig {
	# undef cvspath, expect "ikiwiki"
	# define cvspath normally, get it back
	# define cvspath in a subdir, get it back?
	# define cvspath with extra slashes, get sanitized version back
	# - yoink test_extra_path_slashes
	# undef cvs_wrapper, expect $config{wrappers} same size as before

	my $initial_cvspath = $config{cvspath};
	$config{cvspath} = "/ikiwiki//";
	IkiWiki::checkconfig();
	is(
		$config{cvspath},
		$initial_cvspath,
		q{rcs_recentchanges assumes checkconfig has sanitized cvspath},
	);
}

sub test_getsetup {
	# anything worth testing?
}

sub test_genwrapper {
	# testable directly? affects rcs_add, but are we exercising this?
}


# TESTS FOR VCS PLUGIN API CALLS

sub test_rcs_update {
	# can it assume we're under CVS control? or must it check?
	# anything else worth testing?
}

sub test_rcs_prepedit {
	# can it assume we're under CVS control? or must it check?
	# for existing file, returns latest revision in repo
	# - what's this used for? should it return latest revision in checkout?
	# for new file, returns empty string
}

sub test_rcs_commit {
	# can it assume we're under CVS control? or must it check?
	# if someone else changed the page since rcs_prepedit was called:
	# - try to merge into our working copy
	# - if merge succeeds, proceed to commit
	# - else, return page content with the conflict markers in it
	# commit:
	# - if success, return undef
	# - else, revert + return content with the conflict markers in it
	# git.pm receives "session" param -- useful here?
	# web commits start with "web commit {by,from} "
	# seeing File::chdir errors on commit?
}

sub test_rcs_commit_staged {
	# if commit succeeds, return undef
	# else, warn and return error message (really? or just non-undef?)
}

sub test_rcs_add {
	my $message = "add a top-level ASCII (non-UTF-8) page via VCS API";
	writefile('test0.mdwn', $config{srcdir}, "* some plain ASCII text");
	IkiWiki::rcs_add("test0.mdwn");
	IkiWiki::rcs_commit(
		file => "test0.mdwn",
		message => $message,
		token => "moo",
	);
	is_newly_added("test0.mdwn");
	is_in_keyword_substitution_mode("test0.mdwn", undef);
	my @changes = IkiWiki::rcs_recentchanges(3);
	is_total_number_of_changes(\@changes, 1);
	is_most_recent_change(\@changes, "test0", $message);

	$message = "add a top-level dir via VCS API";
	my $dir1 = "test3";
	can_mkdir($dir1);
	IkiWiki::rcs_add($dir1);
	# XXX test that the wrapper hangs here without our genwrapper()
	# XXX test that the wrapper doesn't hang here with it
	@changes = IkiWiki::rcs_recentchanges(3);
	is_total_number_of_changes(\@changes, 1);	# despite the dir add
	IkiWiki::rcs_commit(
		file => $dir1,
		message => $message,
		token => "oom",
	);
	@changes = IkiWiki::rcs_recentchanges(3);
	is_total_number_of_changes(\@changes, 1);	# dirs aren't tracked

	$message = "add a non-ASCII (UTF-8) text file in an un-added dir";
	my $dir2 = "test4/test5";
	can_mkdir($_) for ('test4', $dir2);
	writefile("$dir2/test1.mdwn", $config{srcdir},readfile("t/test1.mdwn"));
	IkiWiki::rcs_add("$dir2/test1.mdwn");
	IkiWiki::rcs_commit(
		file => "$dir2/test1.mdwn",
		message => $message,
		token => "omo",
	);
	is_newly_added("$dir2/test1.mdwn");
	is_in_keyword_substitution_mode("$dir2/test1.mdwn", undef);
	@changes = IkiWiki::rcs_recentchanges(3);
	is_total_number_of_changes(\@changes, 2);
	is_most_recent_change(\@changes, "$dir2/test1", $message);

	$message = "add a binary file in an un-added dir, and commit_staged";
	my $dir3 = "test6";
	my $file = "$dir3/test7.ico";
	can_mkdir($dir3);
	my $bindata_in = readfile("doc/favicon.ico", 1);
	my $bindata_out = sub { readfile($config{srcdir} . "/$file", 1) };
	writefile($file, $config{srcdir}, $bindata_in, 1);
	is(&$bindata_out(), $bindata_in, q{binary files match before commit});
	IkiWiki::rcs_add($file);
	IkiWiki::rcs_commit_staged(message => $message);
	is_newly_added($file);
	is_in_keyword_substitution_mode($file, q{-kb});
	is(&$bindata_out(), $bindata_in, q{binary files match after commit});
	@changes = IkiWiki::rcs_recentchanges(3);
	is_total_number_of_changes(\@changes, 3);
	is_most_recent_change(\@changes, $file, $message);
	ok(
		unlink($config{srcdir} . "/$file"),
		q{can remove file in order to re-fetch it from repo},
	);
	ok(! -e $config{srcdir} . "/$file", q{really removed file});
	IkiWiki::rcs_update();
	is(&$bindata_out(), $bindata_in, q{binary files match after re-fetch});

	$message = "add a UTF-8 and a binary file in different dirs";
	my $file1 = "test8/test9.mdwn";
	my $file2 = "test10/test11.ico";
	can_mkdir(qw(test8 test10));
	writefile($file1, $config{srcdir}, readfile('t/test2.mdwn'));
	writefile($file2, $config{srcdir}, $bindata_in, 1);
	IkiWiki::rcs_add($_) for ($file1, $file2);
	IkiWiki::rcs_commit_staged(message => $message);
	is_newly_added($_) for ($file1, $file2);
	is_in_keyword_substitution_mode($file1, undef);
	is_in_keyword_substitution_mode($file2, '-kb');
	@changes = IkiWiki::rcs_recentchanges(3);
	is_total_number_of_changes(\@changes, 3);
	@changes = IkiWiki::rcs_recentchanges(4);
	is_total_number_of_changes(\@changes, 4);
	# XXX test for both files in the commit, and no other files
	is_most_recent_change(\@changes, $file2, $message);

	# prevent web edits from attempting to create .../CVS/foo.mdwn
	# on case-insensitive filesystems, also prevent .../cvs/foo.mdwn
	# unless your "CVS" is something else and we've made it configurable

	# can it assume we're under CVS control? or must it check?

	# extract method: filetype-guessing
	# add a binary file, remove it, add a text file by same name, no -kb?
	# add a text file, remove it, add a binary file by same name, -kb?
}

sub test_rcs_remove {
	# can it assume we're under CVS control? or must it check?
	# remove a top-level file
	# - rcs_commit
	# - inspect recentchanges: one new change, file removed
	# remove two files (in different dirs)
	# - rcs_commit_staged
	# - inspect recentchanges: one new change, both files removed
}

sub test_rcs_rename {
	# can it assume we're under CVS control? or must it check?
	# rename a file in the same dir
	# - rcs_commit_staged
	# - inspect recentchanges: one new change, one file removed, one added
	# rename a file into a different dir
	# - rcs_commit_staged
	# - inspect recentchanges: one new change, one file removed, one added
	# rename a file into a not-yet-existing dir
	# - rcs_commit_staged
	# - inspect recentchanges: one new change, one file removed, one added
	# is it safe to use "mv"? what if $dest is somehow outside the wiki?
}

sub test_rcs_recentchanges {
	my $message = "Add a page via CVS directly";
	writefile('test2.mdwn', $config{srcdir}, readfile("t/test2.mdwn"));
	system "cd $config{srcdir}"
		. " && cvs add test2.mdwn >/dev/null 2>&1";
	system "cd $config{srcdir}"
		. " && cvs commit -m \"$message\" test2.mdwn >/dev/null";

	my @changes = IkiWiki::rcs_recentchanges(3);
	is(
		$#changes,
		0,
		q{total commits: 1},
	);
	is(
		$changes[0]{message}[0]{"line"},
		$message,
		q{most recent commit's first message line matches},
	);
	is(
		$changes[0]{pages}[0]{"page"},
		"test2",
		q{most recent commit's first pagename matches},
	);

	# CVS commits run ikiwiki once for every committed file (!)
	# - commit_prep alone should fix this
	# CVS multi-dir commits show only the first dir in recentchanges
	# - commit_prep might also fix this?
	# CVS post-commit hook is amped off to avoid locking against itself
	# - commit_prep probably doesn't fix this... but maybe?
	# can it assume we're under CVS control? or must it check?
	# don't worry whether we're called with a number (we always are)
	# other rcs tests already inspect much of the returned structure
	# CVS commits say "cvs" and get the right committer
	# web commits say "web" and get the right committer
	# - and don't start with "web commit {by,from} "
	# "nickname" -- can we ever meaningfully set this?

	# prefer log_accum, then cvsps, else die
	# run the high-level recentchanges tests 2x (once for each method)
	# - including in other test subs that check recentchanges?
}

sub test_rcs_diff {
	# can it assume we're under CVS control? or must it check?
	# in list context, return all lines (with \n), up to $maxlines if set
	# in scalar context, return the whole diff, up to $maxlines if set
}

sub test_rcs_getctime {
	# can it assume we're under CVS control? or must it check?
	# given a file, find its creation time, else return 0
	# first implement in the obvious way
	# then cache
}

sub test_rcs_getmtime {
	# can it assume we're under CVS control? or must it check?
	# given a file, find its modification time, else return 0
	# first implement in the obvious way
	# then cache
}

sub test_rcs_receive {
	pass(q{rcs_receive doesn't make sense for CVS});
}

sub test_rcs_preprevert {
	# can it assume we're under CVS control? or must it check?
	# given a patchset number, return structure describing what'd happen:
	# - see doc/plugins/write.mdwn:rcs_receive()
	# don't forget about attachments
}

sub test_rcs_revert {
	# can it assume we're under CVS control? or must it check?
	# given a patchset number, stage the revert for rcs_commit_staged()
	# if commit succeeds, return undef
	# else, warn and return error message (really? or just non-undef?)
}

sub main {
	my $test_methods = defined $ENV{TEST_METHOD} 
			 ? $ENV{TEST_METHOD}
			 : $default_test_methods;

	_startup($test_methods eq $default_test_methods);
	_runtests(_get_matching_test_subs($test_methods));
	_shutdown($test_methods eq $default_test_methods);
}

main();


# INTERNAL SUPPORT ROUTINES

sub _plan_for_test_more {
	my $can_plan = shift;

	foreach my $program (@required_programs) {
		my $program_path = `which $program`;
		chomp $program_path;
		return plan(skip_all => "$program not available")
			unless -x $program_path;
	}

	foreach my $module (@required_modules) {
		eval qq{use $module};
		return plan(skip_all => "$module not available")
			if $@;
	}

	return plan(skip_all => "can't create $dir: $!")
		unless mkdir($dir);
	return plan(skip_all => "can't remove $dir: $!")
		unless rmdir($dir);

	return unless $can_plan;

	return plan(tests => $total_tests);
}

# http://stackoverflow.com/questions/607282/whats-the-best-way-to-discover-all-subroutines-a-perl-module-has

use B qw/svref_2object/;

sub in_package {
	my ($coderef, $package) = @_;
	my $cv = svref_2object($coderef);
	return if not $cv->isa('B::CV') or $cv->GV->isa('B::SPECIAL');
	return $cv->GV->STASH->NAME eq $package;
}

sub list_module {
	my $module = shift;
	no strict 'refs';
	return grep {
		defined &{"$module\::$_"} and in_package(\&{*$_}, $module)
	} keys %{"$module\::"};
}


# support for xUnit-style testing, a la Test::Class

sub _startup {
	my $can_plan = shift;
	_plan_for_test_more($can_plan);
	_generate_test_config();
}

sub _shutdown {
	my $had_plan = shift;
	done_testing() unless $had_plan;
}

sub _setup {
	_generate_test_repo();
}

sub _teardown {
	system "rm -rf $dir";
}

sub _runtests {
	my @coderefs = (@_);
	for (@coderefs) {
		_setup();
		$_->();
		_teardown();
	}
}

sub _get_matching_test_subs {
	my $re = shift;
	no strict 'refs';
	return map { \&{*$_} } grep { /$re/ } sort(list_module('main'));
}

sub _generate_test_config {
	%config = IkiWiki::defaultconfig();
	$config{rcs} = "cvs";
	$config{srcdir} = "$dir/src";
	$config{cvsrepo} = "$dir/repo";
	$config{cvspath} = "ikiwiki";
	IkiWiki::loadplugins();
	IkiWiki::checkconfig();
}

sub _generate_test_repo {
	die "can't create $dir: $!"
		unless mkdir($dir);

	my $cvs = "cvs -d $config{cvsrepo}";
	my $dn = ">/dev/null";
	system "$cvs init $dn";
	system "mkdir $dir/$config{cvspath} $dn";
	system "cd $dir/$config{cvspath} && "
		. "$cvs import -m import $config{cvspath} VENDOR RELEASE $dn";
	system "rm -rf $dir/$config{cvspath} $dn";
	system "$cvs co -d $config{srcdir} $config{cvspath} $dn";
}

sub can_mkdir {
	my $dir = shift;
	ok(
		mkdir($config{srcdir} . "/$dir"),
		qq{can mkdir $dir},
	);
}

sub is_newly_added {
	my $file = shift;
	is(
		IkiWiki::Plugin::cvs::cvs_info("Repository revision", $file),
		'1.1',
		qq{$file is newly added to CVS},
	);
}

sub is_in_keyword_substitution_mode {
	my ($file, $mode) = @_;
	$mode = '(none)' unless defined $mode;
	is(
		IkiWiki::Plugin::cvs::cvs_info("Sticky Options", $file),
		$mode,
		qq{$file is in CVS with expected keyword substitution mode},
	);
}

sub is_total_number_of_changes {
	my ($changes, $expected_total) = @_;
	is(
		$#{$changes},
		$expected_total - 1,
		qq{total commits == $expected_total},
	);
}

sub is_most_recent_change {
	my ($changes, $page, $message) = @_;
	is(
		$changes->[0]{message}[0]{"line"},
		$message,
		q{most recent commit's first message line matches},
	);
	is(
		$changes->[0]{pages}[0]{"page"},
		$page,
		q{most recent commit's first pagename matches},
	);
}
