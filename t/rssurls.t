#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 13;

BEGIN { use_ok("IkiWiki::Plugin::inline"); }

# Test the absolute_urls function, used to fix up relative urls for rss
# feeds.
sub test {
	my $input=shift;
	my $baseurl=shift;
	my $expected=shift;
	$expected=~s/URL/$baseurl/g;
	is(IkiWiki::absolute_urls($input, $baseurl), $expected);
	# try it with single quoting -- it's ok if the result comes back
	# double or single-quoted
	$input=~s/"/'/g;
	my $expected_alt=$expected;
	$expected_alt=~s/"/'/g;
	my $ret=IkiWiki::absolute_urls($input, $baseurl);
	ok(($ret eq $expected) || ($ret eq $expected_alt), "$ret vs $expected");
}

sub unchanged {
	test($_[0], $_[1], $_[0]);
}

my $url="http://example.com/blog/foo/";
unchanged("foo", $url);
unchanged('<a href="http://other.com/bar.html">', $url, );
test('<a href="bar.html">', $url, '<a href="URLbar.html">');
test('<a href="/bar.html">', $url, '<a href="http://example.com/bar.html">');
test('<img src="bar.png" />', $url, '<img src="URLbar.png" />');
test('<img src="/bar.png" />', $url, '<img src="http://example.com/bar.png" />');
# off until bug #603736 is fixed
#test('<video controls src="bar.ogg">', $url, '<video controls src="URLbar.ogg">');
