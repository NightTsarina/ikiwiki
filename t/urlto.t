#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 31;

BEGIN { use_ok("IkiWiki"); }

$IkiWiki::config{srcdir} = '/does/not/exist/';
$IkiWiki::config{usedirs} = 1;
$IkiWiki::config{htmlext} = "HTML";
$IkiWiki::config{wiki_file_chars} = "A-Za-z0-9._";

$IkiWiki::config{url} = "http://smcv.example.co.uk";
$IkiWiki::config{cgiurl} = "http://smcv.example.co.uk/cgi-bin/ikiwiki.cgi";
is(IkiWiki::checkconfig(), 1);

# absolute version
is(IkiWiki::cgiurl(cgiurl => $config{cgiurl}), "http://smcv.example.co.uk/cgi-bin/ikiwiki.cgi");
is(IkiWiki::cgiurl(cgiurl => $config{cgiurl}, do => 'badger'), "http://smcv.example.co.uk/cgi-bin/ikiwiki.cgi?do=badger");
is(IkiWiki::urlto('index', undef, 1), "http://smcv.example.co.uk/");
is(IkiWiki::urlto('stoats', undef, 1), "http://smcv.example.co.uk/stoats/");
is(IkiWiki::urlto('', undef, 1), "http://smcv.example.co.uk/");

# "local" (absolute path within site) version (default for cgiurl)
is(IkiWiki::cgiurl(), "/cgi-bin/ikiwiki.cgi");
is(IkiWiki::cgiurl(do => 'badger'), "/cgi-bin/ikiwiki.cgi?do=badger");
is(IkiWiki::baseurl(undef), "/");
is(IkiWiki::urlto('index', undef), "/");
is(IkiWiki::urlto('index'), "/");
is(IkiWiki::urlto('stoats', undef), "/stoats/");
is(IkiWiki::urlto('stoats'), "/stoats/");
is(IkiWiki::urlto(''), "/");

# fully-relative version (default for urlto and baseurl)
is(IkiWiki::baseurl('badger/mushroom'), "../../");
is(IkiWiki::urlto('badger/mushroom', 'snake'), "../badger/mushroom/");
is(IkiWiki::urlto('', 'snake'), "../");
is(IkiWiki::urlto('', 'penguin/herring'), "../../");

# explicit cgiurl override
is(IkiWiki::cgiurl(cgiurl => 'https://foo/ikiwiki'), "https://foo/ikiwiki");
is(IkiWiki::cgiurl(do => 'badger', cgiurl => 'https://foo/ikiwiki'), "https://foo/ikiwiki?do=badger");

# with url and cgiurl on different sites, "local" degrades to protocol-relative
$IkiWiki::config{url} = "http://example.co.uk/~smcv";
$IkiWiki::config{cgiurl} = "http://dynamic.example.co.uk/~smcv/ikiwiki.cgi";
is(IkiWiki::checkconfig(), 1);
is(IkiWiki::cgiurl(), "//dynamic.example.co.uk/~smcv/ikiwiki.cgi");
is(IkiWiki::baseurl(undef), "//example.co.uk/~smcv/");
is(IkiWiki::urlto('stoats', undef), "//example.co.uk/~smcv/stoats/");
is(IkiWiki::urlto('', undef), "//example.co.uk/~smcv/");

# with url and cgiurl on different schemes, "local" degrades to absolute for
# CGI but protocol-relative for static content, to avoid the CGI having
# mixed content
$IkiWiki::config{url} = "http://example.co.uk/~smcv";
$IkiWiki::config{cgiurl} = "https://dynamic.example.co.uk/~smcv/ikiwiki.cgi";
is(IkiWiki::checkconfig(), 1);
is(IkiWiki::cgiurl(), "https://dynamic.example.co.uk/~smcv/ikiwiki.cgi");
is(IkiWiki::baseurl(undef), "//example.co.uk/~smcv/");
is(IkiWiki::urlto('stoats', undef), "//example.co.uk/~smcv/stoats/");
is(IkiWiki::urlto('', undef), "//example.co.uk/~smcv/");
