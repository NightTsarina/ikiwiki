#!/usr/bin/perl
use warnings;
use strict;

use Test::More;

BEGIN {
	my $git = `which git`;
	chomp $git;
	plan(skip_all => 'git not available') unless -x $git;

	plan(skip_all => "CGI not available")
		unless eval q{
			use CGI qw();
			1;
		};

	plan(skip_all => "IPC::Run not available")
		unless eval q{
			use IPC::Run qw(run);
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
	my %setup = (
		wikiname => 'this is the name of my wiki',
		srcdir => getcwd.'/t/tmp/in/doc',
		destdir => getcwd.'/t/tmp/out',
		url => 'http://example.com',
		cgiurl => 'http://example.com/cgi-bin/ikiwiki.cgi',
		cgi_wrapper => getcwd.'/t/tmp/ikiwiki.cgi',
		cgi_wrappermode => '0751',
		add_plugins => [qw(anonok lockedit recentchanges)],
		disable_plugins => [qw(emailauth openid passwordauth)],
		anonok_pagespec => 'writable/*',
		locked_pages => '!writable/*',
		rcs => 'git',
		git_wrapper => getcwd.'/t/tmp/in/.git/hooks/post-commit',
		git_wrappermode => '0754',
		gitorigin_branch => '',
	);
	unless ($installed) {
		$setup{ENV} = { 'PERL5LIB' => getcwd.'/blib/lib' };
	}
	writefile("test.setup", "t/tmp",
		"# IkiWiki::Setup::Yaml - YAML formatted setup file\n" .
		Dump(\%setup));
}

sub thoroughly_rebuild {
	ok(unlink("t/tmp/ikiwiki.cgi") || $!{ENOENT});
	ok(unlink("t/tmp/in/.git/hooks/post-commit") || $!{ENOENT});
	ok(! system(@command, qw(--setup t/tmp/test.setup --rebuild --wrappers)));
}

sub check_cgi_mode_bits {
	my $mode;

	(undef, undef, $mode, undef, undef,
		undef, undef, undef, undef, undef,
		undef, undef, undef) = stat('t/tmp/ikiwiki.cgi');
	is ($mode & 07777, 0751);
	(undef, undef, $mode, undef, undef,
		undef, undef, undef, undef, undef,
		undef, undef, undef) = stat('t/tmp/in/.git/hooks/post-commit');
	is ($mode & 07777, 0754);
}

sub run_cgi {
	my (%args) = @_;
	my ($in, $out);
	my $method = $args{method} || 'GET';
	my $environ = $args{environ} || {};
	my $params = $args{params} || { do => 'prefs' };

	my %defaults = (
		SCRIPT_NAME	=> '/cgi-bin/ikiwiki.cgi',
		HTTP_HOST	=> 'example.com',
	);

	my $cgi = CGI->new($args{params});
	my $query_string = $cgi->query_string();

	if ($method eq 'POST') {
		$defaults{REQUEST_METHOD} = 'POST';
		$in = $query_string;
		$defaults{CONTENT_LENGTH} = length $in;
	} else {
		$defaults{REQUEST_METHOD} = 'GET';
		$defaults{QUERY_STRING} = $query_string;
	}

	my %envvars = (
		%defaults,
		%$environ,
	);
	run(["./t/tmp/ikiwiki.cgi"], \$in, \$out, init => sub {
		map {
			$ENV{$_} = $envvars{$_}
		} keys(%envvars);
	});

	return $out;
}

sub run_git {
	my (undef, $filename, $line) = caller;
	my $args = shift;
	my $desc = shift || join(' ', 'git', @$args);
	my ($in, $out);
	ok(run(['git', @$args], \$in, \$out, init => sub {
		chdir 't/tmp/in' or die $!;
		$ENV{EMAIL} = 'nobody@ikiwiki-tests.invalid';
	}), "$desc at $filename:$line");
	return $out;
}

sub test {
	my $content;
	my $status;

	ok(! system(qw(rm -rf t/tmp)));
	ok(! system(qw(mkdir t/tmp)));

	write_old_file('.gitignore', 't/tmp/in', "/doc/.ikiwiki/\n");
	write_old_file('doc/writable/one.mdwn', 't/tmp/in', 'This is the first test page');
	write_old_file('doc/writable/two.mdwn', 't/tmp/in', 'This is the second test page');
	write_old_file('doc/writable/three.mdwn', 't/tmp/in', 'This is the third test page');

	unless ($installed) {
		ok(! system(qw(cp -pRL doc/wikiicons t/tmp/in/doc/)));
		ok(! system(qw(cp -pRL doc/recentchanges.mdwn t/tmp/in/doc/)));
	}

	run_git(['init']);
	run_git(['add', '.']);
	run_git(['commit', '-m', 'Initial commit']);

	write_setup_file();
	thoroughly_rebuild();
	check_cgi_mode_bits();

	ok(-e 't/tmp/out/writable/one/index.html');
	$content = readfile('t/tmp/out/writable/one/index.html');
	like($content, qr{This is the first test page});
	my $orig_sha1 = run_git(['rev-list', '--max-count=1', 'HEAD']);

	# Test the git hook, which accepts git commits
	writefile('doc/writable/one.mdwn', 't/tmp/in',
		'This is new content for the first test page');
	run_git(['add', '.']);
	run_git(['commit', '-m', 'Git commit']);
	my $first_revertable_sha1 = run_git(['rev-list', '--max-count=1', 'HEAD']);
	isnt($orig_sha1, $first_revertable_sha1);

	ok(-e 't/tmp/out/writable/one/index.html');
	$content = readfile('t/tmp/out/writable/one/index.html');
	like($content, qr{This is new content for the first test page});

	# Test a web commit
	$content = run_cgi(method => 'POST',
		params => {
			do => 'edit',
			page => 'writable/two',
			type => 'mdwn',
			editmessage => 'Web commit',
			editcontent => 'Here is new content for the second page',
			_submit => 'Save Page',
			_submitted => '1',
		},
	);
	like($content, qr{^Status:\s*302\s}m);
	like($content, qr{^Location:\s*http://example\.com/writable/two/\?updated}m);
	my $second_revertable_sha1 = run_git(['rev-list', '--max-count=1', 'HEAD']);
	isnt($orig_sha1, $second_revertable_sha1);
	isnt($first_revertable_sha1, $second_revertable_sha1);

	ok(-e 't/tmp/out/writable/two/index.html');
	$content = readfile('t/tmp/out/writable/two/index.html');
	like($content, qr{Here is new content for the second page});

	# Another edit
	writefile('doc/writable/three.mdwn', 't/tmp/in',
		'Also new content for the third page');
	run_git(['add', '.']);
	run_git(['commit', '-m', 'Git commit']);
	ok(-e 't/tmp/out/writable/three/index.html');
	$content = readfile('t/tmp/out/writable/three/index.html');
	like($content, qr{Also new content for the third page});
	my $third_revertable_sha1 = run_git(['rev-list', '--max-count=1', 'HEAD']);
	isnt($orig_sha1, $third_revertable_sha1);
	isnt($second_revertable_sha1, $third_revertable_sha1);

	run_git(['mv', 'doc/writable/one.mdwn', 'doc/one.mdwn']);
	run_git(['mv', 'doc/writable/two.mdwn', 'two.mdwn']);
	run_git(['commit', '-m', 'Rename files to test CVE-2016-10026']);
	ok(! -e 't/tmp/out/writable/two/index.html');
	ok(! -e 't/tmp/out/writable/one/index.html');
	ok(-e 't/tmp/out/one/index.html');
	my $sha1_before_revert = run_git(['rev-list', '--max-count=1', 'HEAD']);
	isnt($sha1_before_revert, $third_revertable_sha1);

	$content = run_cgi(method => 'post',
		params => {
			do => 'revert',
			revertmessage => 'CVE-2016-10026',
			rev => $first_revertable_sha1,
			_submit => 'Revert',
			_submitted_revert => '1',
		},
	);
	like($content, qr{is locked and cannot be edited});
	# The tree is left clean
	run_git(['diff', '--exit-code']);
	run_git(['diff', '--cached', '--exit-code']);
	my $sha1 = run_git(['rev-list', '--max-count=1', 'HEAD']);
	is($sha1, $sha1_before_revert);

	ok(-e 't/tmp/out/one/index.html');
	ok(! -e 't/tmp/in/doc/writable/one.mdwn');
	ok(-e 't/tmp/in/doc/one.mdwn');
	$content = readfile('t/tmp/out/one/index.html');
	like($content, qr{This is new content for the first test page});

	$content = run_cgi(method => 'post',
		params => {
			do => 'revert',
			revertmessage => 'CVE-2016-10026',
			rev => $second_revertable_sha1,
			_submit => 'Revert',
			_submitted_revert => '1',
		},
	);
	like($content, qr{you are not allowed to change two\.mdwn});
	run_git(['diff', '--exit-code']);
	run_git(['diff', '--cached', '--exit-code']);
	$sha1 = run_git(['rev-list', '--max-count=1', 'HEAD']);
	is($sha1, $sha1_before_revert);

	ok(! -e 't/tmp/out/writable/two/index.html');
	ok(! -e 't/tmp/out/two/index.html');
	ok(! -e 't/tmp/in/doc/writable/two.mdwn');
	ok(-e 't/tmp/in/two.mdwn');
	$content = readfile('t/tmp/in/two.mdwn');
	like($content, qr{Here is new content for the second page});

	# This one can legitimately be reverted
	$content = run_cgi(method => 'post',
		params => {
			do => 'revert',
			revertmessage => 'not CVE-2016-10026',
			rev => $third_revertable_sha1,
			_submit => 'Revert',
			_submitted_revert => '1',
		},
	);
	like($content, qr{^Status:\s*302\s}m);
	like($content, qr{^Location:\s*http://example\.com/recentchanges/}m);
	run_git(['diff', '--exit-code']);
	run_git(['diff', '--cached', '--exit-code']);
	ok(-e 't/tmp/out/writable/three/index.html');
	$content = readfile('t/tmp/out/writable/three/index.html');
	like($content, qr{This is the third test page});
}

test();

done_testing();
