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

# Black-box (ish) test for relative linking between CGI and static content

sub parse_cgi_content {
	my $content = shift;
	my %bits;
	if ($content =~ qr{<base href="([^"]+)" */>}) {
		$bits{basehref} = $1;
	}
	if ($content =~ qr{href="([^"]+/style.css)"}) {
		$bits{stylehref} = $1;
	}
	if ($content =~ qr{class="parentlinks">\s+<a href="([^"]+)">this is the name of my wiki</a>/}s) {
		$bits{tophref} = $1;
	}
	if ($content =~ qr{<a[^>]+href="([^"]+)\?do=prefs"}) {
		$bits{cgihref} = $1;
	}
	return %bits;
}

sub write_old_file {
	my $name = shift;
	my $content = shift;

	writefile($name, "t/tmp/in", $content);
	ok(utime(333333333, 333333333, "t/tmp/in/$name"));
}

sub write_setup_file {
	my (%args) = @_;
	my $urlline = defined $args{url} ? "url: $args{url}" : "";
	my $w3mmodeline = defined $args{w3mmode} ? "w3mmode: $args{w3mmode}" : "";
	my $reverseproxyline = defined $args{reverse_proxy} ? "reverse_proxy: $args{reverse_proxy}" : "";

	writefile("test.setup", "t/tmp", <<EOF
# IkiWiki::Setup::Yaml - YAML formatted setup file
wikiname: this is the name of my wiki
srcdir: t/tmp/in
destdir: t/tmp/out
templatedir: templates
$urlline
cgiurl: $args{cgiurl}
$w3mmodeline
cgi_wrapper: t/tmp/ikiwiki.cgi
cgi_wrappermode: 0754
html5: $args{html5}
# make it easier to test previewing
add_plugins:
- anonok
anonok_pagespec: "*"
$reverseproxyline
ENV: { 'PERL5LIB': 'blib/lib:blib/arch' }
EOF
	);
}

sub thoroughly_rebuild {
	ok(unlink("t/tmp/ikiwiki.cgi") || $!{ENOENT});
	ok(! system("./ikiwiki.out --setup t/tmp/test.setup --rebuild --wrappers"));
}

sub check_cgi_mode_bits {
	my (undef, undef, $mode, undef, undef,
		undef, undef, undef, undef, undef,
		undef, undef, undef) = stat("t/tmp/ikiwiki.cgi");
	is($mode & 07777, 0754);
}

sub check_generated_content {
	my $cgiurl_regex = shift;
	ok(-e "t/tmp/out/a/b/c/index.html");
	my $content = readfile("t/tmp/out/a/b/c/index.html");
	# no <base> on static HTML
	unlike($content, qr{<base\W});
	like($content, $cgiurl_regex);
	# cross-links between static pages are relative
	like($content, qr{<li>A: <a href="../../">a</a></li>});
	like($content, qr{<li>B: <a href="../">b</a></li>});
	like($content, qr{<li>E: <a href="../../d/e/">e</a></li>});
}

sub run_cgi {
	my (%args) = @_;
	my ($in, $out);
	my $is_preview = delete $args{is_preview};
	my $is_https = delete $args{is_https};
	my %defaults = (
		SCRIPT_NAME	=> '/cgi-bin/ikiwiki.cgi',
		HTTP_HOST	=> 'example.com',
	);
	if (defined $is_preview) {
		$defaults{REQUEST_METHOD} = 'POST';
		$in = 'do=edit&page=a/b/c&Preview';
		$defaults{CONTENT_LENGTH} = length $in;
	} else {
		$defaults{REQUEST_METHOD} = 'GET';
		$defaults{QUERY_STRING} = 'do=prefs';
	}
	if (defined $is_https) {
		$defaults{SERVER_PORT} = '443';
		$defaults{HTTPS} = 'on';
	} else {
		$defaults{SERVER_PORT} = '80';
	}
	my %envvars = (
		%defaults,
		%args,
	);
	run(["./t/tmp/ikiwiki.cgi"], \$in, \$out, init => sub {
		map {
			$ENV{$_} = $envvars{$_}
		} keys(%envvars);
	});

	return $out;
}

sub test_startup {
	ok(! system("make -s ikiwiki.out"));
	ok(! system("rm -rf t/tmp"));
	ok(! system("mkdir t/tmp"));

	write_old_file("a.mdwn", "A");
	write_old_file("a/b.mdwn", "B");
	write_old_file("a/b/c.mdwn",
	"* A: [[a]]\n".
	"* B: [[b]]\n".
	"* E: [[a/d/e]]\n");
	write_old_file("a/d.mdwn", "D");
	write_old_file("a/d/e.mdwn", "E");
}

sub test_site1_perfectly_ordinary_ikiwiki {
	write_setup_file(
		html5	=> 0,
		url	=> "http://example.com/wiki/",
		cgiurl	=> "http://example.com/cgi-bin/ikiwiki.cgi",
	);
	thoroughly_rebuild();
	check_cgi_mode_bits();
	# url and cgiurl are on the same host so the cgiurl is host-relative
	check_generated_content(qr{<a[^>]+href="/cgi-bin/ikiwiki.cgi\?do=prefs"});
	my %bits = parse_cgi_content(run_cgi());
	like($bits{basehref}, qr{^(?:(?:http:)?//example\.com)?/wiki/$});
	like($bits{stylehref}, qr{^(?:(?:http:)?//example.com)?/wiki/style.css$});
	like($bits{tophref}, qr{^(?:/wiki|\.)/$});
	like($bits{cgihref}, qr{^(?:(?:http:)?//example.com)?/cgi-bin/ikiwiki.cgi$});

	# when accessed via HTTPS, links are secure
	%bits = parse_cgi_content(run_cgi(is_https => 1));
	like($bits{basehref}, qr{^(?:(?:https:)?//example\.com)?/wiki/$});
	like($bits{stylehref}, qr{^(?:(?:https:)?//example.com)?/wiki/style.css$});
	like($bits{tophref}, qr{^(?:/wiki|\.)/$});
	like($bits{cgihref}, qr{^(?:(?:https:)?//example.com)?/cgi-bin/ikiwiki.cgi$});

	# when accessed via a different hostname, links stay on that host
	%bits = parse_cgi_content(run_cgi(HTTP_HOST => 'staging.example.net'));
	like($bits{basehref}, qr{^(?:(?:http:)?//staging\.example\.net)?/wiki/$});
	like($bits{stylehref}, qr{^(?:(?:http:)?//staging.example.net)?/wiki/style.css$});
	like($bits{tophref}, qr{^(?:/wiki|\.)/$});
	like($bits{cgihref}, qr{^(?:(?:http:)?//staging.example.net)?/cgi-bin/ikiwiki.cgi$});

	# previewing a page
	%bits = parse_cgi_content(run_cgi(is_preview => 1));
	like($bits{basehref}, qr{^(?:(?:http:)?//example\.com)?/wiki/a/b/c/$});
	like($bits{stylehref}, qr{^(?:(?:http:)?//example.com)?/wiki/style.css$});
	like($bits{tophref}, qr{^(?:/wiki|\.\./\.\./\.\.)/$});
	like($bits{cgihref}, qr{^(?:(?:http:)?//example.com)?/cgi-bin/ikiwiki.cgi$});

	# in html5, the <base> is allowed to be relative, and we take full
	# advantage of that
	write_setup_file(
		html5	=> 1,
		url	=> "http://example.com/wiki/",
		cgiurl	=> "http://example.com/cgi-bin/ikiwiki.cgi",
	);
	thoroughly_rebuild();
	check_cgi_mode_bits();
	# url and cgiurl are on the same host so the cgiurl is host-relative
	check_generated_content(qr{<a[^>]+href="/cgi-bin/ikiwiki.cgi\?do=prefs"});

	%bits = parse_cgi_content(run_cgi());
	is($bits{basehref}, "/wiki/");
	is($bits{stylehref}, "/wiki/style.css");
	is($bits{tophref}, "/wiki/");
	is($bits{cgihref}, "/cgi-bin/ikiwiki.cgi");

	# when accessed via HTTPS, links are secure - this is easy because under
	# html5 they're independent of the URL at which the CGI was accessed
	%bits = parse_cgi_content(run_cgi(is_https => 1));
	is($bits{basehref}, "/wiki/");
	is($bits{stylehref}, "/wiki/style.css");
	is($bits{tophref}, "/wiki/");
	is($bits{cgihref}, "/cgi-bin/ikiwiki.cgi");

	# when accessed via a different hostname, links stay on that host -
	# this is really easy in html5 because we can use relative URLs
	%bits = parse_cgi_content(run_cgi(HTTP_HOST => 'staging.example.net'));
	is($bits{basehref}, "/wiki/");
	is($bits{stylehref}, "/wiki/style.css");
	is($bits{tophref}, "/wiki/");
	is($bits{cgihref}, "/cgi-bin/ikiwiki.cgi");

	# previewing a page
	%bits = parse_cgi_content(run_cgi(is_preview => 1));
	is($bits{basehref}, "/wiki/a/b/c/");
	is($bits{stylehref}, "/wiki/style.css");
	like($bits{tophref}, qr{^(?:/wiki|\.\./\.\./\.\.)/$});
	is($bits{cgihref}, "/cgi-bin/ikiwiki.cgi");
}

sub test_site2_static_content_and_cgi_on_different_servers {
	write_setup_file(
		html5	=> 0,
		url	=> "http://static.example.com/",
		cgiurl	=> "http://cgi.example.com/ikiwiki.cgi",
	);
	thoroughly_rebuild();
	check_cgi_mode_bits();
	# url and cgiurl are not on the same host so the cgiurl has to be
	# protocol-relative or absolute
	check_generated_content(qr{<a[^>]+href="(?:http:)?//cgi.example.com/ikiwiki.cgi\?do=prefs"});

	my %bits = parse_cgi_content(run_cgi(SCRIPT_NAME => '/ikiwiki.cgi', HTTP_HOST => 'cgi.example.com'));
	like($bits{basehref}, qr{^(?:(?:http:)?//static.example.com)?/$});
	like($bits{stylehref}, qr{^(?:(?:http:)?//static.example.com)?/style.css$});
	like($bits{tophref}, qr{^(?:http:)?//static.example.com/$});
	like($bits{cgihref}, qr{^(?:(?:http:)?//cgi.example.com)?/ikiwiki.cgi$});

	# when accessed via HTTPS, links are secure
	%bits = parse_cgi_content(run_cgi(is_https => 1, SCRIPT_NAME => '/ikiwiki.cgi', HTTP_HOST => 'cgi.example.com'));
	like($bits{basehref}, qr{^(?:https:)?//static\.example\.com/$});
	like($bits{stylehref}, qr{^(?:(?:https:)?//static.example.com)?/style.css$});
	like($bits{tophref}, qr{^(?:https:)?//static.example.com/$});
	like($bits{cgihref}, qr{^(?:(?:https:)?//cgi.example.com)?/ikiwiki.cgi$});

	# when accessed via a different hostname, links to the CGI (only) should
	# stay on that host?
	%bits = parse_cgi_content(run_cgi(is_preview => 1, SCRIPT_NAME => '/ikiwiki.cgi', HTTP_HOST => 'staging.example.net'));
	like($bits{basehref}, qr{^(?:http:)?//static\.example\.com/a/b/c/$});
	like($bits{stylehref}, qr{^(?:(?:http:)?//static.example.com|\.\./\.\./\.\.)/style.css$});
	like($bits{tophref}, qr{^(?:(?:http:)?//static.example.com|\.\./\.\./\.\.)/$});
	like($bits{cgihref}, qr{^(?:(?:http:)?//(?:staging\.example\.net|cgi\.example\.com))?/ikiwiki.cgi$});
	TODO: {
	local $TODO = "use self-referential CGI URL?";
	like($bits{cgihref}, qr{^(?:(?:http:)?//staging.example.net)?/ikiwiki.cgi$});
	}

	write_setup_file(
		html5	=> 1,
		url	=> "http://static.example.com/",
		cgiurl	=> "http://cgi.example.com/ikiwiki.cgi",
	);
	thoroughly_rebuild();
	check_cgi_mode_bits();
	# url and cgiurl are not on the same host so the cgiurl has to be
	# protocol-relative or absolute
	check_generated_content(qr{<a[^>]+href="(?:http:)?//cgi.example.com/ikiwiki.cgi\?do=prefs"});

	%bits = parse_cgi_content(run_cgi(SCRIPT_NAME => '/ikiwiki.cgi', HTTP_HOST => 'cgi.example.com'));
	is($bits{basehref}, "//static.example.com/");
	is($bits{stylehref}, "//static.example.com/style.css");
	is($bits{tophref}, "//static.example.com/");
	is($bits{cgihref}, "//cgi.example.com/ikiwiki.cgi");

	# when accessed via HTTPS, links are secure - in fact they're exactly the
	# same as when accessed via HTTP
	%bits = parse_cgi_content(run_cgi(is_https => 1, SCRIPT_NAME => '/ikiwiki.cgi', HTTP_HOST => 'cgi.example.com'));
	is($bits{basehref}, "//static.example.com/");
	is($bits{stylehref}, "//static.example.com/style.css");
	is($bits{tophref}, "//static.example.com/");
	is($bits{cgihref}, "//cgi.example.com/ikiwiki.cgi");

	# when accessed via a different hostname, links to the CGI (only) should
	# stay on that host?
	%bits = parse_cgi_content(run_cgi(is_preview => 1, SCRIPT_NAME => '/ikiwiki.cgi', HTTP_HOST => 'staging.example.net'));
	is($bits{basehref}, "//static.example.com/a/b/c/");
	is($bits{stylehref}, "//static.example.com/style.css");
	is($bits{tophref}, "../../../");
	like($bits{cgihref}, qr{//(?:staging\.example\.net|cgi\.example\.com)/ikiwiki\.cgi});
	TODO: {
	local $TODO = "use self-referential CGI URL maybe?";
	is($bits{cgihref}, "//staging.example.net/ikiwiki.cgi");
	}
}

sub test_site3_we_specifically_want_everything_to_be_secure {
	write_setup_file(
		html5	=> 0,
		url	=> "https://example.com/wiki/",
		cgiurl	=> "https://example.com/cgi-bin/ikiwiki.cgi",
	);
	thoroughly_rebuild();
	check_cgi_mode_bits();
	# url and cgiurl are on the same host so the cgiurl is host-relative
	check_generated_content(qr{<a[^>]+href="/cgi-bin/ikiwiki.cgi\?do=prefs"});

	# when accessed via HTTPS, links are secure
	my %bits = parse_cgi_content(run_cgi(is_https => 1));
	like($bits{basehref}, qr{^(?:(?:https:)?//example\.com)?/wiki/$});
	like($bits{stylehref}, qr{^(?:(?:https:)?//example.com)?/wiki/style.css$});
	like($bits{tophref}, qr{^(?:/wiki|\.)/$});
	like($bits{cgihref}, qr{^(?:(?:https:)?//example.com)?/cgi-bin/ikiwiki.cgi$});

	# when not accessed via HTTPS, links should still be secure
	# (but if this happens, that's a sign of web server misconfiguration)
	%bits = parse_cgi_content(run_cgi());
	like($bits{tophref}, qr{^(?:/wiki|\.)/$});
	TODO: {
	local $TODO = "treat https in configured url, cgiurl as required?";
	is($bits{basehref}, "https://example.com/wiki/");
	like($bits{stylehref}, qr{^(?:(?:https:)?//example.com)?/wiki/style.css$});
	}
	like($bits{cgihref}, qr{^(?:(?:https:)?//example.com)?/cgi-bin/ikiwiki.cgi$});

	# when accessed via a different hostname, links stay on that host
	%bits = parse_cgi_content(run_cgi(is_https => 1, HTTP_HOST => 'staging.example.net'));
	like($bits{basehref}, qr{^(?:(?:https:)?//staging\.example\.net)?/wiki/$});
	like($bits{stylehref}, qr{^(?:(?:https:)?//staging.example.net)?/wiki/style.css$});
	like($bits{tophref}, qr{^(?:/wiki|\.)/$});
	like($bits{cgihref}, qr{^(?:(?:https:)?//staging.example.net)?/cgi-bin/ikiwiki.cgi$});

	# previewing a page
	%bits = parse_cgi_content(run_cgi(is_preview => 1, is_https => 1));
	like($bits{basehref}, qr{^(?:(?:https:)?//example\.com)?/wiki/a/b/c/$});
	like($bits{stylehref}, qr{^(?:(?:https:)?//example.com)?/wiki/style.css$});
	like($bits{tophref}, qr{^(?:/wiki|\.\./\.\./\.\.)/$});
	like($bits{cgihref}, qr{^(?:(?:https:)?//example.com)?/cgi-bin/ikiwiki.cgi$});

	# not testing html5: 0 here because that ends up identical to site 1
}

sub test_site4_cgi_is_secure_static_content_doesnt_have_to_be {
	# (NetBSD wiki)
	write_setup_file(
		html5	=> 0,
		url	=> "http://example.com/wiki/",
		cgiurl	=> "https://example.com/cgi-bin/ikiwiki.cgi",
	);
	thoroughly_rebuild();
	check_cgi_mode_bits();
	# url and cgiurl are on the same host but different schemes
	check_generated_content(qr{<a[^>]+href="https://example.com/cgi-bin/ikiwiki.cgi\?do=prefs"});

	# when accessed via HTTPS, links are secure (to avoid mixed-content)
	my %bits = parse_cgi_content(run_cgi(is_https => 1));
	like($bits{basehref}, qr{^(?:(?:https:)?//example\.com)?/wiki/$});
	like($bits{stylehref}, qr{^(?:(?:https:)?//example.com)?/wiki/style.css$});
	like($bits{tophref}, qr{^(?:/wiki|\.)/$});
	like($bits{cgihref}, qr{^(?:(?:https:)?//example.com)?/cgi-bin/ikiwiki.cgi$});

	# FIXME: when not accessed via HTTPS, should the static content be
	# forced to https anyway? For now we accept either
	%bits = parse_cgi_content(run_cgi());
	like($bits{basehref}, qr{^(?:(?:https?)?://example\.com)?/wiki/$});
	like($bits{stylehref}, qr{^(?:(?:https?:)?//example.com)?/wiki/style.css$});
	like($bits{tophref}, qr{^(?:(?:https?://example.com)?/wiki|\.)/$});
	like($bits{cgihref}, qr{^(?:(?:https:)?//example.com)?/cgi-bin/ikiwiki.cgi$});

	# when accessed via a different hostname, links stay on that host
	%bits = parse_cgi_content(run_cgi(is_https => 1, HTTP_HOST => 'staging.example.net'));
	# because the static and dynamic stuff is on the same server, we assume that
	# both are also on the staging server
	like($bits{basehref}, qr{^(?:(?:https:)?//staging\.example\.net)?/wiki/$});
	like($bits{stylehref}, qr{^(?:(?:https:)?//staging.example.net)?/wiki/style.css$});
	like($bits{tophref}, qr{^(?:(?:(?:https:)?//staging.example.net)?/wiki|\.)/$});
	like($bits{cgihref}, qr{^(?:(?:https:)?//(?:staging\.example\.net|example\.com))?/cgi-bin/ikiwiki.cgi$});
	TODO: {
	local $TODO = "this should really point back to itself but currently points to example.com";
	like($bits{cgihref}, qr{^(?:(?:https:)?//staging.example.net)?/cgi-bin/ikiwiki.cgi$});
	}

	# previewing a page
	%bits = parse_cgi_content(run_cgi(is_preview => 1, is_https => 1));
	like($bits{basehref}, qr{^(?:(?:https:)?//example\.com)?/wiki/a/b/c/$});
	like($bits{stylehref}, qr{^(?:(?:https:)?//example.com)?/wiki/style.css$});
	like($bits{tophref}, qr{^(?:/wiki|\.\./\.\./\.\.)/$});
	like($bits{cgihref}, qr{^(?:(?:https:)?//example.com)?/cgi-bin/ikiwiki.cgi$});

	write_setup_file(
		html5	=> 1,
		url	=> "http://example.com/wiki/",
		cgiurl	=> "https://example.com/cgi-bin/ikiwiki.cgi",
	);
	thoroughly_rebuild();
	check_cgi_mode_bits();
	# url and cgiurl are on the same host but different schemes
	check_generated_content(qr{<a[^>]+href="https://example.com/cgi-bin/ikiwiki.cgi\?do=prefs"});

	# when accessed via HTTPS, links are secure (to avoid mixed-content)
	%bits = parse_cgi_content(run_cgi(is_https => 1));
	is($bits{basehref}, "/wiki/");
	is($bits{stylehref}, "/wiki/style.css");
	is($bits{tophref}, "/wiki/");
	like($bits{cgihref}, qr{^(?:(?:https:)?//example.com)?/cgi-bin/ikiwiki.cgi$});

	# when not accessed via HTTPS, ???
	%bits = parse_cgi_content(run_cgi());
	like($bits{basehref}, qr{^(?:https?://example.com)?/wiki/$});
	like($bits{stylehref}, qr{^(?:(?:https?:)?//example.com)?/wiki/style.css$});
	like($bits{tophref}, qr{^(?:(?:https?://example.com)?/wiki|\.)/$});
	like($bits{cgihref}, qr{^(?:(?:https:)?//example.com)?/cgi-bin/ikiwiki.cgi$});

	# when accessed via a different hostname, links stay on that host
	%bits = parse_cgi_content(run_cgi(is_https => 1, HTTP_HOST => 'staging.example.net'));
	# because the static and dynamic stuff is on the same server, we assume that
	# both are also on the staging server
	is($bits{basehref}, "/wiki/");
	is($bits{stylehref}, "/wiki/style.css");
	like($bits{tophref}, qr{^(?:/wiki|\.)/$});
	TODO: {
	local $TODO = "this should really point back to itself but currently points to example.com";
	like($bits{cgihref}, qr{^(?:(?:https:)?//staging\.example\.net)?/cgi-bin/ikiwiki.cgi$});
	}

	# previewing a page
	%bits = parse_cgi_content(run_cgi(is_preview => 1, is_https => 1));
	is($bits{basehref}, "/wiki/a/b/c/");
	is($bits{stylehref}, "/wiki/style.css");
	like($bits{tophref}, qr{^(?:/wiki|\.\./\.\./\.\.)/$});
	like($bits{cgihref}, qr{^(?:(?:https:)?//example.com)?/cgi-bin/ikiwiki.cgi$});

	# Deliberately not testing https static content with http cgiurl,
	# because that makes remarkably little sense.
}

sub test_site5_w3mmode {
	# as documented in [[w3mmode]]
	write_setup_file(
		html5	=> 0, 
		url	=> undef,
		cgiurl	=> "ikiwiki.cgi",
		w3mmode	=> 1,
	);
	thoroughly_rebuild();
	check_cgi_mode_bits();
	# FIXME: does /$LIB/ikiwiki-w3m.cgi work under w3m?
	check_generated_content(qr{<a[^>]+href="(?:file://)?/\$LIB/ikiwiki-w3m.cgi/ikiwiki.cgi\?do=prefs"});

	my %bits = parse_cgi_content(run_cgi(PATH_INFO => '/ikiwiki.cgi', SCRIPT_NAME => '/cgi-bin/ikiwiki-w3m.cgi'));
	my $pwd = getcwd();
	like($bits{tophref}, qr{^(?:\Q$pwd\E/t/tmp/out|\.)/$});
	like($bits{cgihref}, qr{^(?:file://)?/\$LIB/ikiwiki-w3m.cgi/ikiwiki.cgi$});
	like($bits{basehref}, qr{^(?:(?:file:)?//)?\Q$pwd\E/t/tmp/out/$});
	like($bits{stylehref}, qr{^(?:(?:(?:file:)?//)?\Q$pwd\E/t/tmp/out|\.)/style.css$});

	write_setup_file(
		html5	=> 1,
		url	=> undef,
		cgiurl	=> "ikiwiki.cgi",
		w3mmode	=> 1,
	);
	thoroughly_rebuild();
	check_cgi_mode_bits();
	# FIXME: does /$LIB/ikiwiki-w3m.cgi work under w3m?
	check_generated_content(qr{<a[^>]+href="(?:file://)?/\$LIB/ikiwiki-w3m.cgi/ikiwiki.cgi\?do=prefs"});

	%bits = parse_cgi_content(run_cgi(PATH_INFO => '/ikiwiki.cgi', SCRIPT_NAME => '/cgi-bin/ikiwiki-w3m.cgi'));
	like($bits{tophref}, qr{^(?:\Q$pwd\E/t/tmp/out|\.)/$});
	like($bits{cgihref}, qr{^(?:file://)?/\$LIB/ikiwiki-w3m.cgi/ikiwiki.cgi$});
	like($bits{basehref}, qr{^(?:(?:file:)?//)?\Q$pwd\E/t/tmp/out/$});
	like($bits{stylehref}, qr{^(?:(?:(?:file:)?//)?\Q$pwd\E/t/tmp/out|\.)/style.css$});
}

sub test_site6_behind_reverse_proxy {
	write_setup_file(
		html5	=> 0,
		url	=> "https://example.com/wiki/",
		cgiurl	=> "https://example.com/cgi-bin/ikiwiki.cgi",
		reverse_proxy => 1,
	);
	thoroughly_rebuild();
	check_cgi_mode_bits();
	# url and cgiurl are on the same host so the cgiurl is host-relative
	check_generated_content(qr{<a[^>]+href="/cgi-bin/ikiwiki.cgi\?do=prefs"});

	# because we are behind a reverse-proxy we must assume that
	# we're being accessed by the configured cgiurl
	my %bits = parse_cgi_content(run_cgi(HTTP_HOST => 'localhost'));
	like($bits{tophref}, qr{^(?:/wiki|\.)/$});
	like($bits{cgihref}, qr{^(?:(?:https:)?//example.com)?/cgi-bin/ikiwiki.cgi$});
	like($bits{basehref}, qr{^(?:(?:https:)?//example\.com)?/wiki/$});
	like($bits{stylehref}, qr{^(?:(?:https:)?//example.com)?/wiki/style.css$});

	# previewing a page
	%bits = parse_cgi_content(run_cgi(is_preview => 1, HTTP_HOST => 'localhost'));
	like($bits{tophref}, qr{^(?:/wiki|\.\./\.\./\.\.)/$});
	like($bits{cgihref}, qr{^(?:(?:https:)?//example.com)?/cgi-bin/ikiwiki.cgi$});
	like($bits{basehref}, qr{^(?:(?:https)?://example\.com)?/wiki/a/b/c/$});
	like($bits{stylehref}, qr{^(?:(?:https:)?//example.com)?/wiki/style.css$});

	# not testing html5: 1 because it would be the same as site 1 -
	# the reverse_proxy config option is unnecessary under html5
}

test_startup();

test_site1_perfectly_ordinary_ikiwiki();
test_site2_static_content_and_cgi_on_different_servers();
test_site3_we_specifically_want_everything_to_be_secure();
test_site4_cgi_is_secure_static_content_doesnt_have_to_be();
test_site5_w3mmode();
test_site6_behind_reverse_proxy();

done_testing();
