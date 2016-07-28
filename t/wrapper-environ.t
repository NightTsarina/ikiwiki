#!/usr/bin/perl
use warnings;
use strict;

use Test::More;
plan(skip_all => "IPC::Run not available")
	unless eval q{
		use IPC::Run qw(run);
		1;
	};

use IkiWiki;

use Cwd qw(getcwd);
use Errno qw(ENOENT);

my $installed = $ENV{INSTALLED_TESTS};

my @command;
if ($installed) {
	@command = qw(env PERL5LIB=t/tmp ikiwiki);
}
else {
	ok(! system("make -s ikiwiki.out"));
	@command = (qw(env PERL5LIB=t/tmp:blib/lib:blib/arch perl),
		"-I".getcwd, qw(./ikiwiki.out
		--underlaydir=underlays/basewiki
		--set underlaydirbase=underlays
		--templatedir=templates));
}

writefile("test.setup", "t/tmp", <<EOF
# IkiWiki::Setup::Yaml - YAML formatted setup file
wikiname: this is the name of my wiki
srcdir: t/tmp/in
destdir: t/tmp/out
url: http://localhost
cgiurl: http://localhost/ikiwiki.cgi
cgi_wrapper: t/tmp/ikiwiki.cgi
cgi_wrappermode: 0754
add_plugins:
- anonok
- excessiveenvironment
anonok_pagespec: "*"
ENV: { 'PERL5LIB': 't/tmp:blib/lib:blib/arch' }
EOF
	);

writefile("index.mdwn", "t/tmp/in", "");

writefile("IkiWiki/Plugin/excessiveenvironment.pm", "t/tmp", <<'EOF'
#!/usr/bin/perl
package IkiWiki::Plugin::excessiveenvironment;
use warnings;
use strict;
use IkiWiki;

sub import {
	hook(type => "getsetup", id => "excessiveenvironment", call => \&getsetup);
	hook(type => "genwrapper", id => "excessiveenvironment", call => \&genwrapper);
}

sub getsetup {
	return plugin => {
		safe => 0,
		rebuild => undef,
		section => "rcs",
	};
}

sub genwrapper {
	my @ret;
	foreach my $j (1..4096) {
		push @ret, qq{addenv("VAR$j", "val$j");\n};
	}
	return join '', @ret;
}

1;
EOF
	);

my $stdout;
ok(! system(@command, qw(--setup t/tmp/test.setup --rebuild --wrappers)), "run ikiwiki");
ok(run(["./t/tmp/ikiwiki.cgi"], '<&-', '>', \$stdout, init => sub {
	$ENV{HTTP_HOST} = "localhost";
	$ENV{QUERY_STRING} = "do=prefs";
	$ENV{REQUEST_METHOD} = "GET";
	$ENV{SCRIPT_NAME} = "/cgi-bin/ikiwiki.cgi";
	$ENV{SERVER_PORT} = "80"
}), "run CGI");

done_testing();
