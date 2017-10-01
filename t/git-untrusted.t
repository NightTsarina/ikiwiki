#!/usr/bin/perl
use warnings;
use strict;

use File::Temp;
use Test::More;

BEGIN {
	my $git = `which git`;
	chomp $git;
	plan(skip_all => 'git not available') unless -x $git;

	plan(skip_all => "IPC::Run not available")
		unless eval q{
			use IPC::Run qw(run start);
			1;
		};

	use_ok('IkiWiki');
	use_ok('YAML::XS');
}

# We check for English error messages
$ENV{LC_ALL} = 'C';

use Cwd qw(getcwd);
use Errno qw(ENOENT);

my $installed = $ENV{INSTALLED_TESTS};
my $tmp = File::Temp->newdir(CLEANUP => 0);

my @command;
if ($installed) {
	@command = qw(ikiwiki);
}
else {
	ok(! system("make -s ikiwiki.out"));
	@command = ("perl", "-I".getcwd."/blib/lib", './ikiwiki.out',
		'--underlaydir='.getcwd.'/underlays/basewiki',
		'--set', 'underlaydirbase='.getcwd.'/underlays',
		'--templatedir='.getcwd.'/templates');
}

sub write_old_file {
	my $name = shift;
	my $dir = shift;
	my $content = shift;
	writefile($name, $dir, $content);
	ok(utime(333333333, 333333333, "$dir/$name"));
}

sub write_setup_file {
	my %params = @_;
	my %setup = (
		wikiname => 'this is the name of my wiki',
		srcdir => "$tmp/srcdir",
		destdir => "$tmp/out",
		url => 'http://example.com',
		cgiurl => 'http://example.com/cgi-bin/ikiwiki.cgi',
		cgi_wrapper => "$tmp/ikiwiki.cgi",
		cgi_wrappermode => '0755',
		add_plugins => [qw(anonok attachment lockedit recentchanges)],
		disable_plugins => [qw(emailauth openid passwordauth)],
		anonok_pagespec => 'writable/*',
		locked_pages => '!writable/*',
		rcs => 'git',
		git_wrapper => "$tmp/repo.git/hooks/post-update",
		git_wrappermode => '0755',
		gitorigin_branch => 'test-repo',
		gitmaster_branch => 'master',
		untrusted_committers => [$params{trustme} ? 'nobody' : scalar getpwuid($<)],
		git_test_receive_wrapper => "$tmp/repo.git/hooks/pre-receive",
		ENV => { LC_ALL => 'C' },
		verbose => 1,
	);
	unless ($installed) {
		$setup{ENV}{'PERL5LIB'} = getcwd.'/blib/lib';
	}
	writefile("test.setup", "$tmp",
		"# IkiWiki::Setup::Yaml - YAML formatted setup file\n" .
		Dump(\%setup));
}

sub thoroughly_rebuild {
	ok(unlink("$tmp/ikiwiki.cgi") || $!{ENOENT});
	ok(unlink("$tmp/repo.git/hooks/post-update") || $!{ENOENT});
	ok(unlink("$tmp/repo.git/hooks/pre-receive") || $!{ENOENT});
	ok(! system(@command, qw(--setup), "$tmp/test.setup", qw(--rebuild --wrappers)));
}

sub try_run_git {
	my $args = shift;
	my %params = @_;
	my $git_dir = $params{chdir} || "$tmp/srcdir";
	my ($in, $out, $err);
	my @redirections = ('>', \$in);
	if ($params{capture_stdout}) {
		push @redirections, '>', \$out;
	}
	else {
		push @redirections, '>', \*STDERR;
	}
	push @redirections, '2>', \$err if $params{capture_stderr};
	my $h = start(['git', @$args], @redirections, init => sub {
		chdir $git_dir or die $!;
		my $name = 'The IkiWiki Tests';
		my $email = 'nobody@ikiwiki-tests.invalid';
		if ($args->[0] eq 'commit') {
			$ENV{GIT_AUTHOR_NAME} = $ENV{GIT_COMMITTER_NAME} = $name;
			$ENV{GIT_AUTHOR_EMAIL} = $ENV{GIT_COMMITTER_EMAIL} = $email;
		}
	});
	while ($h->pump) {};
	$h->finish;
	return $h, $out, $err;
}

sub run_git {
	my (undef, $filename, $line) = caller;
	my $args = shift;
	my %params = @_;
	my $git_dir = $params{chdir} || "$tmp/srcdir";
	my $desc = $params{desc} || join(' ', 'git', @$args);
	my ($h, $out, $err) = try_run_git($args, capture_stdout => 1, %params);
	is($h->full_result(0), 0, "'$desc' in $git_dir at $filename:$line");
	return $out;
}

sub test {
	my ($h, $out, $err);
	my $sha1;

	write_old_file('.gitignore', "$tmp/srcdir", "/.ikiwiki/\n");
	write_old_file('writable/one.mdwn', "$tmp/srcdir", 'This is the first test page');
	write_old_file('writable/two.bin', "$tmp/srcdir", 'An attachment');

	unless ($installed) {
		ok(! system(qw(cp -pRL doc/wikiicons), "$tmp/srcdir/"));
		ok(! system(qw(cp -pRL doc/recentchanges.mdwn), "$tmp/srcdir/"));
	}

	ok(mkdir "$tmp/repo.git");
	run_git(['init', '--bare'], chdir => "$tmp/repo.git");

	run_git(['init']);
	run_git(['add', '.']);
	run_git(['commit', '-m', 'Initial commit']);
	my $initial_sha1 = run_git(['rev-list', '--max-count=1', 'HEAD']);
	run_git(['remote', 'add', 'test-repo', "$tmp/repo.git"]);
	run_git(['push', 'test-repo', 'master:master']);
	run_git(['branch', '--set-upstream-to=test-repo/master']);

	run_git(['clone', '-otest-repo', "$tmp/repo.git", "$tmp/clone"], chdir => $tmp);
	writefile('writable/untrusted_user_says_hi.mdwn', "$tmp/clone", 'Hi!');
	run_git(['add', 'writable'], chdir => "$tmp/clone");
	run_git(['commit', '-m', 'Hi'], chdir => "$tmp/clone");
	my $allowed_sha1 = run_git(['rev-list', '--max-count=1', 'HEAD'],
		chdir => "$tmp/clone");

	diag 'Pushing unrestricted change as untrusted user';
	write_setup_file(trustme => 0);
	thoroughly_rebuild();

	$out = run_git([
		'push', 'test-repo', 'master:master',
	], chdir => "$tmp/clone");
	$sha1 = run_git(['rev-list', '--max-count=1', 'HEAD'], chdir => "$tmp/repo.git");
	is($sha1, $allowed_sha1, 'allowed commit was pushed');
	$sha1 = run_git(['rev-list', '--max-count=1', 'HEAD']);
	is($sha1, $allowed_sha1, 'allowed commit was pushed');
	ok(-e "$tmp/srcdir/writable/untrusted_user_says_hi.mdwn");
	ok(-e "$tmp/out/writable/untrusted_user_says_hi/index.html");

	diag 'Pushing restricted change as untrusted user';
	writefile('staff_only.mdwn', "$tmp/clone", 'Hi!');
	run_git(['add', 'staff_only.mdwn'], chdir => "$tmp/clone");
	run_git(['commit', '-m', 'Hi'], chdir => "$tmp/clone");
	my $proposed_sha1 = run_git(['rev-list', '--max-count=1', 'HEAD'],
		chdir => "$tmp/clone");

	($h, $out, $err) = try_run_git([
		'push', 'test-repo', 'master:master',
	], chdir => "$tmp/clone", capture_stdout => 1, capture_stderr => 1);
	isnt($h->full_result(0), 0);
	is($out, '');
	like($err, qr{remote: <.*>staff only</.*> is locked and cannot be edited});
	$sha1 = run_git(['rev-list', '--max-count=1', 'HEAD'], chdir => "$tmp/repo.git");
	is($sha1, $allowed_sha1, 'proposed commit was not pushed');
	$sha1 = run_git(['rev-list', '--max-count=1', 'HEAD']);
	is($sha1, $allowed_sha1, 'proposed commit was not pushed');
	ok(! -e "$tmp/srcdir/staff_only.mdwn");
	ok(! -e "$tmp/out/staff_only/index.html");

	diag 'Pushing restricted change as trusted user';
	write_setup_file(trustme => 1);
	thoroughly_rebuild();

	$out = run_git([
		'push', 'test-repo', 'master:master',
	], chdir => "$tmp/clone");
	$sha1 = run_git(['rev-list', '--max-count=1', 'HEAD'], chdir => "$tmp/repo.git");
	is($sha1, $proposed_sha1, 'proposed commit was pushed');
	$sha1 = run_git(['rev-list', '--max-count=1', 'HEAD']);
	is($sha1, $proposed_sha1, 'proposed commit was pushed');
	ok(-e "$tmp/srcdir/staff_only.mdwn");
	ok(-e "$tmp/out/staff_only/index.html");
}

test();

done_testing();
