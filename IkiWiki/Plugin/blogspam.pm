#!/usr/bin/perl
package IkiWiki::Plugin::blogspam;

use warnings;
use strict;
use IkiWiki 3.00;
use Encode;

my $defaulturl='http://test.blogspam.net:9999/';
my $client;

sub import {
	hook(type => "getsetup", id => "blogspam",  call => \&getsetup);
	hook(type => "checkconfig", id => "blogspam", call => \&checkconfig);
	hook(type => "checkcontent", id => "blogspam", call => \&checkcontent);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 0,
			section => "auth",
		},
		blogspam_pagespec => {
			type => 'pagespec',
			example => 'postcomment(*)',
			description => 'PageSpec of pages to check for spam',
			link => 'ikiwiki/PageSpec',
			safe => 1,
			rebuild => 0,
		},
		blogspam_options => {
			type => "string",
			example => "blacklist=1.2.3.4,blacklist=8.7.6.5,max-links=10",
			description => "options to send to blogspam server",
			link => "http://blogspam.net/api/2.0/testComment.html#options",
			safe => 1,
			rebuild => 0,
		},
		blogspam_server => {
			type => "string",
			default => $defaulturl,
			description => "blogspam server JSON url",
			safe => 1,
			rebuild => 0,
		},
}

sub checkconfig () {
	# This is done at checkconfig time because printing an error
	# if the module is missing when a spam is posted would not
	# let the admin know about the problem.
	eval q{
		use JSON;
		use HTTP::Request;
	};
	error $@ if $@;

	eval q{use LWPx::ParanoidAgent};
	if (!$@) {
		$client=LWPx::ParanoidAgent->new(agent => $config{useragent});
	}
	else {
		eval q{use LWP};
		if ($@) {
			error $@;
			return;
		}
		$client=useragent();
	}
}

sub checkcontent (@) {
	my %params=@_;
	my $session=$params{session};
	
	my $spec='!admin()';
 	if (exists $config{blogspam_pagespec} &&
	    length $config{blogspam_pagespec}) {
		$spec.=" and (".$config{blogspam_pagespec}.")";
	}

	my $user=$session->param("name");
	return undef unless pagespec_match($params{page}, $spec,
		(defined $user ? (user => $user) : ()),
		(defined $session->remote_addr() ? (ip => $session->remote_addr()) : ()),
		location => $params{page});

	my $url=$defaulturl;
	$url = $config{blogspam_server} if exists $config{blogspam_server};

	my @options = split(",", $config{blogspam_options})
		if exists $config{blogspam_options};

	# Allow short comments and whitespace-only edits, unless the user
	# has overridden min-words themselves.
	push @options, "min-words=0"
		unless grep /^min-words=/i, @options;
	# Wiki pages can have a lot of urls, unless the user specifically
	# wants to limit them.
	push @options, "exclude=lotsaurls"
		unless grep /^max-links/i, @options;
	# Unless the user specified a size check, disable such checking.
	push @options, "exclude=size"
		unless grep /^(?:max|min)-size/i, @options;
	# This test has absurd false positives on words like "alpha"
	# and "buy".
	push @options, "exclude=stopwords";

	my %req=(
		ip => $session->remote_addr(),
		comment => encode_utf8(defined $params{diff} ? $params{diff} : $params{content}),
		subject => encode_utf8(defined $params{subject} ? $params{subject} : ""),
		name => encode_utf8(defined $params{author} ? $params{author} : ""),
		link => encode_utf8(exists $params{url} ? $params{url} : ""),
		options => join(",", @options),
		site => encode_utf8($config{url}),
		version => "ikiwiki ".$IkiWiki::version,
	);
	eval q{use JSON; use HTTP::Request}; # errors handled in checkconfig()
	my $res = $client->request(
		HTTP::Request->new(
			'POST',
			$url,
			[ 'Content-Type' => 'application/json' ],
			to_json(\%req),
		),
	);

	if (! ref $res || ! $res->is_success()) {
		debug("failed to get response from blogspam server ($url)");
		return undef;
	}
	my $details = from_json($res->content);
	if ($details->{result} eq 'SPAM') {
		eval q{use Data::Dumper};
		debug("blogspam server reports $details->{reason}: ".Dumper(\%req));
		return gettext("Sorry, but that looks like spam to <a href=\"http://blogspam.net/\">blogspam</a>: ").$details->{reason};
	}
	elsif ($details->{result} ne 'OK') {
		debug("blogspam server failure: ".$res->content);
		return undef;
	}
	else {
		return undef;
	}
}

1
