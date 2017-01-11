#!/usr/bin/perl
use warnings;
use strict;

use Cwd qw(getcwd);
use Test::More;

BEGIN {
	plan(skip_all => "Authen::Passphrase not available")
		unless eval q{
			use Authen::Passphrase qw();
			1;
		};

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
	use_ok('IkiWiki::Plugin::passwordauth');
	use_ok('IkiWiki::Setup');
	use_ok('IkiWiki::UserInfo');
	use_ok('YAML::XS');
}

# We check for English messages
$ENV{LC_ALL} = 'C';

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

sub write_setup_file {
	my %setup = (
		wikiname => 'this is the name of my wiki',
		srcdir => getcwd.'/t/tmp/in',
		destdir => getcwd.'/t/tmp/out',
		url => 'http://example.com',
		cgiurl => 'http://example.com/cgi-bin/ikiwiki.cgi',
		cgi_wrapper => getcwd.'/t/tmp/ikiwiki.cgi',
		cgi_wrappermode => '0751',
		add_plugins => [qw(anonok attachment lockedit passwordauth recentchanges)],
		adminuser => [qw(alice)],
		disable_plugins => [qw(emailauth openid)],
		locked_pages => '*',
	);
	unless ($installed) {
		$setup{ENV} = { 'PERL5LIB' => getcwd.'/blib/lib' };
	}
	writefile("test.setup", "t/tmp",
		"# IkiWiki::Setup::Yaml - YAML formatted setup file\n" .
		Dump(\%setup));
	%IkiWiki::config = IkiWiki::defaultconfig();
	IkiWiki::Setup::load("t/tmp/test.setup");
	IkiWiki::loadplugins();
	IkiWiki::checkconfig();
}

sub thoroughly_rebuild {
	ok(unlink("t/tmp/ikiwiki.cgi") || $!{ENOENT});
	ok(unlink("t/tmp/in/.git/hooks/post-commit") || $!{ENOENT});
	ok(! system(@command, qw(--setup t/tmp/test.setup --rebuild --wrappers)));
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
	print("# $query_string\n");
	run(["./t/tmp/ikiwiki.cgi"], \$in, \$out, init => sub {
		map {
			$ENV{$_} = $envvars{$_}
		} keys(%envvars);
	});

	return $out;
}

sub test_prefs {
	my $content;
	my $status;

	IkiWiki::userinfo_setall('alice', {regdate => time, email => 'alice@example.com'});
	IkiWiki::userinfo_setall('bob', {regdate => time, email => 'bob@example.com'});
	IkiWiki::userinfo_setall('name', {regdate => time, email => 'nobody@example.com'});
	IkiWiki::Plugin::passwordauth::setpassword('alice', "Alice's password");
	IkiWiki::Plugin::passwordauth::setpassword('bob', "Bob's password");

	$content = run_cgi(
		params => {
			do => 'prefs',
		},
	);

	# prefs requires signing in so we are redirected, with the postsignin
	# action saved in the session
	like($content, qr/<form .*name="signin"/);

	# remember the cookie so we can continue to act in that session
	my ($cookie) = ($content =~ m/^Set-Cookie: (.*)$/im);

	# sign in
	$content = run_cgi(
		environ => {
			HTTP_COOKIE => $cookie,
		},
		params => {
			do => 'signin',
			name => 'bob',
			password => "Bob's password",
			_submit => 'Login',
			_submitted_signin => '1',
		},
	);

	# We are signed-in as bob now
	like($content, qr{page=bob.*Create your user page});
	like($content, qr{<input.*name="name".*value="bob"});
	like($content, qr{<input.*name="email".*value="bob\@example.com"});
}

sub test_formbuilder_disaster {
	my $content;
	my $status;

	ok(! system(qw(rm -rf t/tmp)));
	ok(! system(qw(mkdir t/tmp)));
	ok(! system(qw(mkdir t/tmp/in)));

	write_setup_file();
	thoroughly_rebuild();

	IkiWiki::userinfo_setall('alice', {regdate => time, email => 'alice@example.com'});
	IkiWiki::userinfo_setall('bob', {regdate => time, email => 'bob@example.com'});
	IkiWiki::userinfo_setall('name', {regdate => time, email => 'nobody@example.com'});
	IkiWiki::Plugin::passwordauth::setpassword('alice', "Alice's password");
	IkiWiki::Plugin::passwordauth::setpassword('bob', "Bob's password");

	$content = run_cgi(
		params => {
			do => 'prefs',
		},
	);

	# prefs requires signing in so we are redirected, with the postsignin
	# action saved in the session
	like($content, qr/<form .*name="signin"/);

	# remember the cookie so we can continue to act in that session
	my ($cookie) = ($content =~ m/^Set-Cookie: (.*)$/im);

	# sign in
	$content = run_cgi(
		environ => {
			HTTP_COOKIE => $cookie,
		},
		params => {
			do => 'signin',
			name => ['bob', 'name', 'alice'],
			password => "Bob's password",
			_submit => 'Login',
			_submitted_signin => '1',
		},
	);

	like($content, qr{page=bob.*Create your user page});
	like($content, qr{<input.*name="name".*value="bob"});
	like($content, qr{<input.*name="email".*value="bob\@example.com"});

	unlike($content, qr{alice});
}

ok(! system(qw(rm -rf t/tmp)));
ok(! system(qw(mkdir t/tmp)));
ok(! system(qw(mkdir t/tmp/in)));

write_setup_file();
thoroughly_rebuild();

test_prefs();
test_formbuilder_disaster();

done_testing();
