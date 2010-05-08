#!/usr/bin/perl
use warnings;
use strict;

BEGIN {
	eval q{
		use Net::OpenID::VerifiedIdentity;
	};
	if ($@) {
		eval q{use Test::More skip_all => "Net::OpenID::VerifiedIdentity not available"};
	}
	else {
		eval q{use Test::More tests => 11};
	}
	use_ok("IkiWiki");
}

# Some typical examples:

# This test, when run by Test::Harness using perl -w, exposes a warning in
# Net::OpenID::VerifiedIdentity. Normally that warning is not displayed, as
# that module does not use warnings. To avoid cluttering the test output,
# disable the -w switch temporarily.
$^W=0;
is(IkiWiki::openiduser('http://josephturian.blogspot.com'), 'josephturian [blogspot.com]');
$^W=1;

is(IkiWiki::openiduser('http://yam655.livejournal.com/'), 'yam655 [livejournal.com]');
is(IkiWiki::openiduser('http://id.mayfirst.org/jamie/'), 'jamie [id.mayfirst.org]');

# yahoo has an anchor in the url
is(IkiWiki::openiduser('https://me.yahoo.com/joeyhess#35f22'), 'joeyhess [me.yahoo.com]');
# google urls are horrendous, but the worst bit is after a ?, so can be dropped
is(IkiWiki::openiduser('https://www.google.com/accounts/o8/id?id=AItOawm-ebiIfxbKD3KNa-Cu9LvvD9edMLW7BAo'), 'id [www.google.com/accounts/o8]');

# and some less typical ones taken from the ikiwiki commit history

is(IkiWiki::openiduser('http://thm.id.fedoraproject.org/'), 'thm [id.fedoraproject.org]');
is(IkiWiki::openiduser('http://dtrt.org/'), 'dtrt.org');
is(IkiWiki::openiduser('http://alcopop.org/me/openid/'), 'openid [alcopop.org/me]');
is(IkiWiki::openiduser('http://id.launchpad.net/882/bielawski1'), 'bielawski1 [id.launchpad.net/882]');
is(IkiWiki::openiduser('http://technorati.com/people/technorati/drajt'), 'drajt [technorati.com/people/technorati]');
