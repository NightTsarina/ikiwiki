#!/usr/bin/perl
use warnings;
use strict;

use Cwd qw(getcwd);
use Errno qw(ENOENT);

BEGIN {
	if (!eval q{
		use IPC::Run qw(run);
		1;
	}) {
		eval q{use Test::More skip_all => "IPC::Run not available"};
	}
	else {
		eval q{use Test::More};
	}
	use_ok("IkiWiki");
}

my $PERL5LIB = 'blib/lib:blib/arch';
my $pwd = getcwd();

# Black-box (ish) test for relative linking between CGI and static content

my $blob;
my ($content, $in, %bits);

sub parse_cgi_content {
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

ok(! system("make -s ikiwiki.out"));
ok(! system("rm -rf t/tmp"));
ok(! system("mkdir t/tmp"));

sub write_old_file {
	my $name = shift;
	my $content = shift;

	writefile($name, "t/tmp/in", $content);
	ok(utime(333333333, 333333333, "t/tmp/in/$name"));
}

write_old_file("a.mdwn", "A");
write_old_file("a/b.mdwn", "B");
write_old_file("a/b/c.mdwn",
"* A: [[a]]\n".
"* B: [[b]]\n".
"* E: [[a/d/e]]\n");
write_old_file("a/d.mdwn", "D");
write_old_file("a/d/e.mdwn", "E");

#######################################################################
# site 1: a perfectly ordinary ikiwiki

writefile("test.setup", "t/tmp", <<EOF
# IkiWiki::Setup::Yaml - YAML formatted setup file
wikiname: this is the name of my wiki
srcdir: t/tmp/in
destdir: t/tmp/out
templatedir: templates
url: "http://example.com/wiki/"
cgiurl: "http://example.com/cgi-bin/ikiwiki.cgi"
cgi_wrapper: t/tmp/ikiwiki.cgi
cgi_wrappermode: 0754
# make it easier to test previewing
add_plugins:
- anonok
anonok_pagespec: "*"
ENV: { 'PERL5LIB': '$PERL5LIB' }
EOF
);

ok(unlink("t/tmp/ikiwiki.cgi") || $!{ENOENT});
ok(! system("./ikiwiki.out --setup t/tmp/test.setup --rebuild --wrappers"));

# CGI wrapper should be exactly the requested mode
my (undef, undef, $mode, undef, undef,
	undef, undef, undef, undef, undef,
	undef, undef, undef) = stat("t/tmp/ikiwiki.cgi");
is($mode & 07777, 0754);

ok(-e "t/tmp/out/a/b/c/index.html");
$content = readfile("t/tmp/out/a/b/c/index.html");
# no <base> on static HTML
unlike($content, qr{<base\W});
# url and cgiurl are on the same host so the cgiurl is host-relative
like($content, qr{<a[^>]+href="/cgi-bin/ikiwiki.cgi\?do=prefs"});
# cross-links between static pages are relative
like($content, qr{<li>A: <a href="../../">a</a></li>});
like($content, qr{<li>B: <a href="../">b</a></li>});
like($content, qr{<li>E: <a href="../../d/e/">e</a></li>});

run(["./t/tmp/ikiwiki.cgi"], \undef, \$content, init => sub {
	$ENV{REQUEST_METHOD} = 'GET';
	$ENV{SERVER_PORT} = '80';
	$ENV{SCRIPT_NAME} = '/cgi-bin/ikiwiki.cgi';
	$ENV{QUERY_STRING} = 'do=prefs';
	$ENV{HTTP_HOST} = 'example.com';
});
%bits = parse_cgi_content($content);
is($bits{basehref}, "http://example.com/wiki/");
like($bits{stylehref}, qr{^(?:(?:http:)?//example.com)?/wiki/style.css$});
like($bits{tophref}, qr{^(?:/wiki|\.)/$});
like($bits{cgihref}, qr{^(?:(?:http:)?//example.com)?/cgi-bin/ikiwiki.cgi$});

# when accessed via HTTPS, links are secure
run(["./t/tmp/ikiwiki.cgi"], \undef, \$content, init => sub {
	$ENV{REQUEST_METHOD} = 'GET';
	$ENV{SERVER_PORT} = '443';
	$ENV{SCRIPT_NAME} = '/cgi-bin/ikiwiki.cgi';
	$ENV{QUERY_STRING} = 'do=prefs';
	$ENV{HTTP_HOST} = 'example.com';
	$ENV{HTTPS} = 'on';
});
%bits = parse_cgi_content($content);
is($bits{basehref}, "https://example.com/wiki/");
like($bits{stylehref}, qr{^(?:(?:https:)?//example.com)?/wiki/style.css$});
like($bits{tophref}, qr{^(?:/wiki|\.)/$});
like($bits{cgihref}, qr{^(?:(?:https:)?//example.com)?/cgi-bin/ikiwiki.cgi$});

# when accessed via a different hostname, links stay on that host
run(["./t/tmp/ikiwiki.cgi"], \undef, \$content, init => sub {
	$ENV{REQUEST_METHOD} = 'GET';
	$ENV{SERVER_PORT} = '80';
	$ENV{SCRIPT_NAME} = '/cgi-bin/ikiwiki.cgi';
	$ENV{QUERY_STRING} = 'do=prefs';
	$ENV{HTTP_HOST} = 'staging.example.net';
});
%bits = parse_cgi_content($content);
is($bits{basehref}, "http://staging.example.net/wiki/");
like($bits{stylehref}, qr{^(?:(?:http:)?//staging.example.net)?/wiki/style.css$});
like($bits{tophref}, qr{^(?:/wiki|\.)/$});
like($bits{cgihref}, qr{^(?:(?:http:)?//staging.example.net)?/cgi-bin/ikiwiki.cgi$});

# previewing a page
$in = 'do=edit&page=a/b/c&Preview';
run(["./t/tmp/ikiwiki.cgi"], \$in, \$content, init => sub {
	$ENV{REQUEST_METHOD} = 'POST';
	$ENV{SERVER_PORT} = '80';
	$ENV{SCRIPT_NAME} = '/cgi-bin/ikiwiki.cgi';
	$ENV{HTTP_HOST} = 'example.com';
	$ENV{CONTENT_LENGTH} = length $in;
});
%bits = parse_cgi_content($content);
is($bits{basehref}, "http://example.com/wiki/a/b/c/");
like($bits{stylehref}, qr{^(?:(?:http:)?//example.com)?/wiki/style.css$});
like($bits{tophref}, qr{^(?:/wiki|\.\./\.\./\.\.)/$});
like($bits{cgihref}, qr{^(?:(?:http:)?//example.com)?/cgi-bin/ikiwiki.cgi$});

#######################################################################
# site 2: static content and CGI are on different servers

writefile("test.setup", "t/tmp", <<EOF
# IkiWiki::Setup::Yaml - YAML formatted setup file
wikiname: this is the name of my wiki
srcdir: t/tmp/in
destdir: t/tmp/out
templatedir: templates
url: "http://static.example.com/"
cgiurl: "http://cgi.example.com/ikiwiki.cgi"
cgi_wrapper: t/tmp/ikiwiki.cgi
cgi_wrappermode: 0754
# make it easier to test previewing
add_plugins:
- anonok
anonok_pagespec: "*"
ENV: { 'PERL5LIB': '$PERL5LIB' }
EOF
);

ok(unlink("t/tmp/ikiwiki.cgi"));
ok(! system("./ikiwiki.out --setup t/tmp/test.setup --rebuild --wrappers"));

# CGI wrapper should be exactly the requested mode
(undef, undef, $mode, undef, undef,
	undef, undef, undef, undef, undef,
	undef, undef, undef) = stat("t/tmp/ikiwiki.cgi");
is($mode & 07777, 0754);

ok(-e "t/tmp/out/a/b/c/index.html");
$content = readfile("t/tmp/out/a/b/c/index.html");
# no <base> on static HTML
unlike($content, qr{<base\W});
# url and cgiurl are not on the same host so the cgiurl has to be
# protocol-relative or absolute
like($content, qr{<a[^>]+href="(?:http:)?//cgi.example.com/ikiwiki.cgi\?do=prefs"});
# cross-links between static pages are still relative
like($content, qr{<li>A: <a href="../../">a</a></li>});
like($content, qr{<li>B: <a href="../">b</a></li>});
like($content, qr{<li>E: <a href="../../d/e/">e</a></li>});

run(["./t/tmp/ikiwiki.cgi"], \undef, \$content, init => sub {
	$ENV{REQUEST_METHOD} = 'GET';
	$ENV{SERVER_PORT} = '80';
	$ENV{SCRIPT_NAME} = '/ikiwiki.cgi';
	$ENV{QUERY_STRING} = 'do=prefs';
	$ENV{HTTP_HOST} = 'cgi.example.com';
});
%bits = parse_cgi_content($content);
like($bits{basehref}, qr{^http://static.example.com/$});
like($bits{stylehref}, qr{^(?:(?:http:)?//static.example.com)?/style.css$});
like($bits{tophref}, qr{^(?:http:)?//static.example.com/$});
like($bits{cgihref}, qr{^(?:(?:http:)?//cgi.example.com)?/ikiwiki.cgi$});

# when accessed via HTTPS, links are secure
run(["./t/tmp/ikiwiki.cgi"], \undef, \$content, init => sub {
	$ENV{REQUEST_METHOD} = 'GET';
	$ENV{SERVER_PORT} = '443';
	$ENV{SCRIPT_NAME} = '/ikiwiki.cgi';
	$ENV{QUERY_STRING} = 'do=prefs';
	$ENV{HTTP_HOST} = 'cgi.example.com';
	$ENV{HTTPS} = 'on';
});
%bits = parse_cgi_content($content);
like($bits{basehref}, qr{^https://static.example.com/$});
like($bits{stylehref}, qr{^(?:(?:https:)?//static.example.com)?/style.css$});
like($bits{tophref}, qr{^(?:https:)?//static.example.com/$});
like($bits{cgihref}, qr{^(?:(?:https:)?//cgi.example.com)?/ikiwiki.cgi$});

# when accessed via a different hostname, links to the CGI (only) should
# stay on that host?
$in = 'do=edit&page=a/b/c&Preview';
run(["./t/tmp/ikiwiki.cgi"], \$in, \$content, init => sub {
	$ENV{REQUEST_METHOD} = 'POST';
	$ENV{SERVER_PORT} = '80';
	$ENV{SCRIPT_NAME} = '/ikiwiki.cgi';
	$ENV{HTTP_HOST} = 'staging.example.net';
	$ENV{CONTENT_LENGTH} = length $in;
});
%bits = parse_cgi_content($content);
like($bits{basehref}, qr{^http://static.example.com/a/b/c/$});
like($bits{stylehref}, qr{^(?:(?:http:)?//static.example.com|\.\./\.\./\.\.)/style.css$});
like($bits{tophref}, qr{^(?:(?:http:)?//static.example.com|\.\./\.\./\.\.)/$});
TODO: {
local $TODO = "use self-referential CGI URL?";
like($bits{cgihref}, qr{^(?:(?:http:)?//staging.example.net)?/ikiwiki.cgi$});
}

#######################################################################
# site 3: we specifically want everything to be secure

writefile("test.setup", "t/tmp", <<EOF
# IkiWiki::Setup::Yaml - YAML formatted setup file
wikiname: this is the name of my wiki
srcdir: t/tmp/in
destdir: t/tmp/out
templatedir: templates
url: "https://example.com/wiki/"
cgiurl: "https://example.com/cgi-bin/ikiwiki.cgi"
cgi_wrapper: t/tmp/ikiwiki.cgi
cgi_wrappermode: 0754
# make it easier to test previewing
add_plugins:
- anonok
anonok_pagespec: "*"
ENV: { 'PERL5LIB': '$PERL5LIB' }
EOF
);

ok(unlink("t/tmp/ikiwiki.cgi"));
ok(! system("./ikiwiki.out --setup t/tmp/test.setup --rebuild --wrappers"));

# CGI wrapper should be exactly the requested mode
(undef, undef, $mode, undef, undef,
	undef, undef, undef, undef, undef,
	undef, undef, undef) = stat("t/tmp/ikiwiki.cgi");
is($mode & 07777, 0754);

ok(-e "t/tmp/out/a/b/c/index.html");
$content = readfile("t/tmp/out/a/b/c/index.html");
# no <base> on static HTML
unlike($content, qr{<base\W});
# url and cgiurl are on the same host so the cgiurl is host-relative
like($content, qr{<a[^>]+href="/cgi-bin/ikiwiki.cgi\?do=prefs"});
# cross-links between static pages are relative
like($content, qr{<li>A: <a href="../../">a</a></li>});
like($content, qr{<li>B: <a href="../">b</a></li>});
like($content, qr{<li>E: <a href="../../d/e/">e</a></li>});

# when accessed via HTTPS, links are secure
run(["./t/tmp/ikiwiki.cgi"], \undef, \$content, init => sub {
	$ENV{REQUEST_METHOD} = 'GET';
	$ENV{SERVER_PORT} = '443';
	$ENV{SCRIPT_NAME} = '/cgi-bin/ikiwiki.cgi';
	$ENV{QUERY_STRING} = 'do=prefs';
	$ENV{HTTP_HOST} = 'example.com';
	$ENV{HTTPS} = 'on';
});
%bits = parse_cgi_content($content);
is($bits{basehref}, "https://example.com/wiki/");
like($bits{stylehref}, qr{^(?:(?:https:)?//example.com)?/wiki/style.css$});
like($bits{tophref}, qr{^(?:/wiki|\.)/$});
like($bits{cgihref}, qr{^(?:(?:https:)?//example.com)?/cgi-bin/ikiwiki.cgi$});

# when not accessed via HTTPS, links should still be secure
# (but if this happens, that's a sign of web server misconfiguration)
run(["./t/tmp/ikiwiki.cgi"], \undef, \$content, init => sub {
	$ENV{REQUEST_METHOD} = 'GET';
	$ENV{SERVER_PORT} = '80';
	$ENV{SCRIPT_NAME} = '/cgi-bin/ikiwiki.cgi';
	$ENV{QUERY_STRING} = 'do=prefs';
	$ENV{HTTP_HOST} = 'example.com';
});
%bits = parse_cgi_content($content);
like($bits{tophref}, qr{^(?:/wiki|\.)/$});
TODO: {
local $TODO = "treat https in configured url, cgiurl as required?";
is($bits{basehref}, "https://example.com/wiki/");
like($bits{stylehref}, qr{^(?:(?:https:)?//example.com)?/wiki/style.css$});
}
like($bits{cgihref}, qr{^(?:(?:https:)?//example.com)?/cgi-bin/ikiwiki.cgi$});

# when accessed via a different hostname, links stay on that host
run(["./t/tmp/ikiwiki.cgi"], \undef, \$content, init => sub {
	$ENV{REQUEST_METHOD} = 'GET';
	$ENV{SERVER_PORT} = '443';
	$ENV{SCRIPT_NAME} = '/cgi-bin/ikiwiki.cgi';
	$ENV{QUERY_STRING} = 'do=prefs';
	$ENV{HTTP_HOST} = 'staging.example.net';
	$ENV{HTTPS} = 'on';
});
%bits = parse_cgi_content($content);
is($bits{basehref}, "https://staging.example.net/wiki/");
like($bits{stylehref}, qr{^(?:(?:https:)?//staging.example.net)?/wiki/style.css$});
like($bits{tophref}, qr{^(?:/wiki|\.)/$});
like($bits{cgihref}, qr{^(?:(?:https:)?//staging.example.net)?/cgi-bin/ikiwiki.cgi$});

# previewing a page
$in = 'do=edit&page=a/b/c&Preview';
run(["./t/tmp/ikiwiki.cgi"], \$in, \$content, init => sub {
	$ENV{REQUEST_METHOD} = 'POST';
	$ENV{SERVER_PORT} = '443';
	$ENV{SCRIPT_NAME} = '/cgi-bin/ikiwiki.cgi';
	$ENV{HTTP_HOST} = 'example.com';
	$ENV{CONTENT_LENGTH} = length $in;
	$ENV{HTTPS} = 'on';
});
%bits = parse_cgi_content($content);
is($bits{basehref}, "https://example.com/wiki/a/b/c/");
like($bits{stylehref}, qr{^(?:(?:https:)?//example.com)?/wiki/style.css$});
like($bits{tophref}, qr{^(?:/wiki|\.\./\.\./\.\.)/$});
like($bits{cgihref}, qr{^(?:(?:https:)?//example.com)?/cgi-bin/ikiwiki.cgi$});

#######################################################################
# site 4 (NetBSD wiki): CGI is secure, static content doesn't have to be

writefile("test.setup", "t/tmp", <<EOF
# IkiWiki::Setup::Yaml - YAML formatted setup file
wikiname: this is the name of my wiki
srcdir: t/tmp/in
destdir: t/tmp/out
templatedir: templates
url: "http://example.com/wiki/"
cgiurl: "https://example.com/cgi-bin/ikiwiki.cgi"
cgi_wrapper: t/tmp/ikiwiki.cgi
cgi_wrappermode: 0754
# make it easier to test previewing
add_plugins:
- anonok
anonok_pagespec: "*"
ENV: { 'PERL5LIB': '$PERL5LIB' }
EOF
);

ok(unlink("t/tmp/ikiwiki.cgi"));
ok(! system("./ikiwiki.out --setup t/tmp/test.setup --rebuild --wrappers"));

# CGI wrapper should be exactly the requested mode
(undef, undef, $mode, undef, undef,
	undef, undef, undef, undef, undef,
	undef, undef, undef) = stat("t/tmp/ikiwiki.cgi");
is($mode & 07777, 0754);

ok(-e "t/tmp/out/a/b/c/index.html");
$content = readfile("t/tmp/out/a/b/c/index.html");
# no <base> on static HTML
unlike($content, qr{<base\W});
# url and cgiurl are on the same host but different schemes
like($content, qr{<a[^>]+href="https://example.com/cgi-bin/ikiwiki.cgi\?do=prefs"});
# cross-links between static pages are relative
like($content, qr{<li>A: <a href="../../">a</a></li>});
like($content, qr{<li>B: <a href="../">b</a></li>});
like($content, qr{<li>E: <a href="../../d/e/">e</a></li>});

# when accessed via HTTPS, links are secure (to avoid mixed-content)
run(["./t/tmp/ikiwiki.cgi"], \undef, \$content, init => sub {
	$ENV{REQUEST_METHOD} = 'GET';
	$ENV{SERVER_PORT} = '443';
	$ENV{SCRIPT_NAME} = '/cgi-bin/ikiwiki.cgi';
	$ENV{QUERY_STRING} = 'do=prefs';
	$ENV{HTTP_HOST} = 'example.com';
	$ENV{HTTPS} = 'on';
});
%bits = parse_cgi_content($content);
is($bits{basehref}, "https://example.com/wiki/");
like($bits{stylehref}, qr{^(?:(?:https:)?//example.com)?/wiki/style.css$});
like($bits{tophref}, qr{^(?:/wiki|\.)/$});
like($bits{cgihref}, qr{^(?:(?:https:)?//example.com)?/cgi-bin/ikiwiki.cgi$});

# when not accessed via HTTPS, ???
run(["./t/tmp/ikiwiki.cgi"], \undef, \$content, init => sub {
	$ENV{REQUEST_METHOD} = 'GET';
	$ENV{SERVER_PORT} = '80';
	$ENV{SCRIPT_NAME} = '/cgi-bin/ikiwiki.cgi';
	$ENV{QUERY_STRING} = 'do=prefs';
	$ENV{HTTP_HOST} = 'example.com';
});
%bits = parse_cgi_content($content);
like($bits{basehref}, qr{^https?://example.com/wiki/$});
like($bits{stylehref}, qr{^(?:(?:https?:)?//example.com)?/wiki/style.css$});
like($bits{tophref}, qr{^(?:(?:https?://example.com)?/wiki|\.)/$});
like($bits{cgihref}, qr{^(?:(?:https:)?//example.com)?/cgi-bin/ikiwiki.cgi$});

# when accessed via a different hostname, links stay on that host
run(["./t/tmp/ikiwiki.cgi"], \undef, \$content, init => sub {
	$ENV{REQUEST_METHOD} = 'GET';
	$ENV{SERVER_PORT} = '443';
	$ENV{SCRIPT_NAME} = '/cgi-bin/ikiwiki.cgi';
	$ENV{QUERY_STRING} = 'do=prefs';
	$ENV{HTTP_HOST} = 'staging.example.net';
	$ENV{HTTPS} = 'on';
});
%bits = parse_cgi_content($content);
# because the static and dynamic stuff is on the same server, we assume that
# both are also on the staging server
like($bits{basehref}, qr{^https://staging.example.net/wiki/$});
like($bits{stylehref}, qr{^(?:(?:https:)?//staging.example.net)?/wiki/style.css$});
like($bits{tophref}, qr{^(?:(?:(?:https:)?//staging.example.net)?/wiki|\.)/$});
TODO: {
local $TODO = "this should really point back to itself but currently points to example.com";
like($bits{cgihref}, qr{^(?:(?:https:)?//staging.example.net)?/cgi-bin/ikiwiki.cgi$});
}

# previewing a page
$in = 'do=edit&page=a/b/c&Preview';
run(["./t/tmp/ikiwiki.cgi"], \$in, \$content, init => sub {
	$ENV{REQUEST_METHOD} = 'POST';
	$ENV{SERVER_PORT} = '443';
	$ENV{SCRIPT_NAME} = '/cgi-bin/ikiwiki.cgi';
	$ENV{HTTP_HOST} = 'example.com';
	$ENV{CONTENT_LENGTH} = length $in;
	$ENV{HTTPS} = 'on';
});
%bits = parse_cgi_content($content);
is($bits{basehref}, "https://example.com/wiki/a/b/c/");
like($bits{stylehref}, qr{^(?:(?:https:)?//example.com)?/wiki/style.css$});
like($bits{tophref}, qr{^(?:/wiki|\.\./\.\./\.\.)/$});
like($bits{cgihref}, qr{^(?:(?:https:)?//example.com)?/cgi-bin/ikiwiki.cgi$});

# Deliberately not testing https static content with http cgiurl,
# because that makes remarkably little sense.

#######################################################################
# site 5: w3mmode, as documented in [[w3mmode]]

writefile("test.setup", "t/tmp", <<EOF
# IkiWiki::Setup::Yaml - YAML formatted setup file
wikiname: this is the name of my wiki
srcdir: t/tmp/in
destdir: t/tmp/out
templatedir: templates
cgiurl: ikiwiki.cgi
w3mmode: 1
cgi_wrapper: t/tmp/ikiwiki.cgi
cgi_wrappermode: 0754
add_plugins:
- anonok
anonok_pagespec: "*"
ENV: { 'PERL5LIB': '$PERL5LIB' }
EOF
);

ok(unlink("t/tmp/ikiwiki.cgi"));
ok(! system("./ikiwiki.out --setup t/tmp/test.setup --rebuild --wrappers"));

# CGI wrapper should be exactly the requested mode
(undef, undef, $mode, undef, undef,
	undef, undef, undef, undef, undef,
	undef, undef, undef) = stat("t/tmp/ikiwiki.cgi");
is($mode & 07777, 0754);

ok(-e "t/tmp/out/a/b/c/index.html");
$content = readfile("t/tmp/out/a/b/c/index.html");
# no <base> on static HTML
unlike($content, qr{<base\W});
# FIXME: does /$LIB/ikiwiki-w3m.cgi work under w3m?
like($content, qr{<a[^>]+href="(?:file://)?/\$LIB/ikiwiki-w3m.cgi/ikiwiki.cgi\?do=prefs"});
# cross-links between static pages are still relative
like($content, qr{<li>A: <a href="../../">a</a></li>});
like($content, qr{<li>B: <a href="../">b</a></li>});
like($content, qr{<li>E: <a href="../../d/e/">e</a></li>});

run(["./t/tmp/ikiwiki.cgi"], \undef, \$content, init => sub {
	$ENV{REQUEST_METHOD} = 'GET';
	$ENV{PATH_INFO} = '/ikiwiki.cgi';
	$ENV{SCRIPT_NAME} = '/cgi-bin/ikiwiki-w3m.cgi';
	$ENV{QUERY_STRING} = 'do=prefs';
});
%bits = parse_cgi_content($content);
like($bits{tophref}, qr{^(?:\Q$pwd\E/t/tmp/out|\.)/$});
like($bits{cgihref}, qr{^(?:file://)?/\$LIB/ikiwiki-w3m.cgi/ikiwiki.cgi$});
like($bits{basehref}, qr{^(?:(?:file:)?//)?\Q$pwd\E/t/tmp/out/$});
like($bits{stylehref}, qr{^(?:(?:(?:file:)?//)?\Q$pwd\E/t/tmp/out|\.)/style.css$});

#######################################################################
# site 6: we're behind a reverse-proxy

writefile("test.setup", "t/tmp", <<EOF
# IkiWiki::Setup::Yaml - YAML formatted setup file
wikiname: this is the name of my wiki
srcdir: t/tmp/in
destdir: t/tmp/out
templatedir: templates
url: "https://example.com/wiki/"
cgiurl: "https://example.com/cgi-bin/ikiwiki.cgi"
cgi_wrapper: t/tmp/ikiwiki.cgi
cgi_wrappermode: 0754
# make it easier to test previewing
add_plugins:
- anonok
anonok_pagespec: "*"
reverse_proxy: 1
ENV: { 'PERL5LIB': '$PERL5LIB' }
EOF
);

ok(unlink("t/tmp/ikiwiki.cgi"));
ok(! system("./ikiwiki.out --setup t/tmp/test.setup --rebuild --wrappers"));

# CGI wrapper should be exactly the requested mode
(undef, undef, $mode, undef, undef,
	undef, undef, undef, undef, undef,
	undef, undef, undef) = stat("t/tmp/ikiwiki.cgi");
is($mode & 07777, 0754);

ok(-e "t/tmp/out/a/b/c/index.html");
$content = readfile("t/tmp/out/a/b/c/index.html");
# no <base> on static HTML
unlike($content, qr{<base\W});
# url and cgiurl are on the same host so the cgiurl is host-relative
like($content, qr{<a[^>]+href="/cgi-bin/ikiwiki.cgi\?do=prefs"});
# cross-links between static pages are relative
like($content, qr{<li>A: <a href="../../">a</a></li>});
like($content, qr{<li>B: <a href="../">b</a></li>});
like($content, qr{<li>E: <a href="../../d/e/">e</a></li>});

# because we are behind a reverse-proxy we must assume that
# we're being accessed by the configured cgiurl
run(["./t/tmp/ikiwiki.cgi"], \undef, \$content, init => sub {
	$ENV{REQUEST_METHOD} = 'GET';
	$ENV{SERVER_PORT} = '80';
	$ENV{SCRIPT_NAME} = '/cgi-bin/ikiwiki.cgi';
	$ENV{QUERY_STRING} = 'do=prefs';
	$ENV{HTTP_HOST} = 'localhost';
});
%bits = parse_cgi_content($content);
like($bits{tophref}, qr{^(?:/wiki|\.)/$});
like($bits{cgihref}, qr{^(?:(?:https:)?//example.com)?/cgi-bin/ikiwiki.cgi$});
is($bits{basehref}, "https://example.com/wiki/");
like($bits{stylehref}, qr{^(?:(?:https:)?//example.com)?/wiki/style.css$});

# previewing a page
$in = 'do=edit&page=a/b/c&Preview';
run(["./t/tmp/ikiwiki.cgi"], \$in, \$content, init => sub {
	$ENV{REQUEST_METHOD} = 'POST';
	$ENV{SERVER_PORT} = '80';
	$ENV{SCRIPT_NAME} = '/cgi-bin/ikiwiki.cgi';
	$ENV{HTTP_HOST} = 'localhost';
	$ENV{CONTENT_LENGTH} = length $in;
});
%bits = parse_cgi_content($content);
like($bits{tophref}, qr{^(?:/wiki|\.\./\.\./\.\.)/$});
like($bits{cgihref}, qr{^(?:(?:https:)?//example.com)?/cgi-bin/ikiwiki.cgi$});
is($bits{basehref}, "https://example.com/wiki/a/b/c/");
like($bits{stylehref}, qr{^(?:(?:https:)?//example.com)?/wiki/style.css$});

done_testing;
