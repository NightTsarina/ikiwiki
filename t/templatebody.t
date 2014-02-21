#!/usr/bin/perl
package IkiWiki;

use warnings;
use strict;
use Test::More tests => 18;

BEGIN { use_ok("IkiWiki"); }
BEGIN { use_ok("IkiWiki::Render"); }
BEGIN { use_ok("IkiWiki::Plugin::templatebody"); }
BEGIN { use_ok("IkiWiki::Plugin::mdwn"); }
BEGIN { use_ok("IkiWiki::Plugin::tag"); }
BEGIN { use_ok("IkiWiki::Plugin::template"); }

sub assert_pagespec_matches {
	my $page = shift;
	my $spec = shift;
	my @params = @_;
	@params = (location => 'index') unless @params;

	my $res = pagespec_match($page, $spec, @params);

	if ($res) {
		pass($res);
	}
	else {
		fail($res);
	}
}

sub assert_pagespec_doesnt_match {
	my $page = shift;
	my $spec = shift;
	my @params = @_;
	@params = (location => 'index') unless @params;

	my $res = pagespec_match($page, $spec, @params);

	if (ref $res && $res->isa("IkiWiki::ErrorReason")) {
		fail($res);
	}
	elsif ($res) {
		fail($res);
	}
	else {
		pass($res);
	}
}

ok(! system("rm -rf t/tmp; mkdir t/tmp t/tmp/src t/tmp/dst"));

$config{verbose} = 1;
$config{srcdir} = 't/tmp/src';
$config{underlaydir} = 't/tmp/src';
$config{destdir} = 't/tmp/dst';
$config{underlaydirbase} = '.';
$config{templatedir} = 'templates';
$config{usedirs} = 1;
$config{htmlext} = 'html';
$config{wiki_file_chars} = "-[:alnum:]+/.:_";
$config{default_pageext} = "mdwn";
$config{wiki_file_prune_regexps} = [qr/^\./];

is(checkconfig(), 1);

%oldrenderedfiles=%pagectime=();
%pagesources=%pagemtime=%oldlinks=%links=%depends=%typedlinks=%oldtypedlinks=
%destsources=%renderedfiles=%pagecase=%pagestate=();

$pagesources{index} = "index.mdwn";
$pagemtime{index} = $pagectime{index} = 1000000;
writefile("index.mdwn", "t/tmp/src", <<EOF
[[!template id="deftmpl" greeting="hello" them="world"]]
[[!template id="oldtmpl" greeting="greetings" them="earthlings"]]
EOF
);

$pagesources{"templates/deftmpl"} = "templates/deftmpl.mdwn";
$pagemtime{index} = $pagectime{index} = 1000000;
writefile("templates/deftmpl.mdwn", "t/tmp/src", <<EOF
[[!templatebody <<ENDBODY
<p><b><TMPL_VAR GREETING>, <TMPL_VAR THEM></b></p>
[[!tag greeting]]
ENDBODY]]

This template says hello to someone.
[[!tag documentation]]
EOF
);

$pagesources{"templates/oldtmpl"} = "templates/oldtmpl.mdwn";
$pagemtime{index} = $pagectime{index} = 1000000;
writefile("templates/oldtmpl.mdwn", "t/tmp/src", <<EOF
<p><i><TMPL_VAR GREETING>, <TMPL_VAR THEM></i></p>
EOF
);

my %content;

foreach my $page (keys %pagesources) {
	my $content = readfile("t/tmp/src/$pagesources{$page}");
	$content = IkiWiki::filter($page, $page, $content);
	$content = IkiWiki::preprocess($page, $page, $content);
	$content{$page} = $content;
}

# Templates are expanded
like($content{index}, qr{<p><b>hello, world</b></p>});
like($content{index}, qr{<p><i>greetings, earthlings</i></p>});
assert_pagespec_matches('index', 'tagged(greeting)');
# The documentation from the templatebody-using page is not expanded
unlike($content{index}, qr{This template says hello to someone});
assert_pagespec_doesnt_match('index', 'tagged(documentation)');

# In the templatebody-using page, the documentation is expanded
like($content{'templates/deftmpl'}, qr{This template says hello to someone});
assert_pagespec_matches('templates/deftmpl', 'tagged(documentation)');
# In the templatebody-using page, the template is *not* expanded
unlike($content{'templates/deftmpl'}, qr{<p><b>hello, world</b></p>});
unlike($content{'templates/deftmpl'}, qr{<p><i>greetings, earthlings</i></p>});
assert_pagespec_doesnt_match('templates/deftmpl', 'tagged(greeting)');

1;
