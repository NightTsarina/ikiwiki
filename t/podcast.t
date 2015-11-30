#!/usr/bin/perl
use warnings;
use strict;

BEGIN {
	eval q{use XML::Feed; use HTML::Parser; use HTML::LinkExtor; use File::MimeInfo};
	if ($@) {
		eval q{use Test::More skip_all =>
			"XML::Feed and/or HTML::Parser or File::MimeInfo not available"};
	}
	else {
		eval q{use Test::More tests => 137};
	}
}

use Cwd;
use File::Basename;

my $installed = $ENV{INSTALLED_TESTS};

my @base_command;
if ($installed) {
	ok(1, "running installed");
	@base_command = qw(ikiwiki);
}
else {
	ok(! system("make -s ikiwiki.out"));
	@base_command = qw(perl -I. ./ikiwiki.out
		--underlaydir=underlays/basewiki
		--set underlaydirbase=underlays
		--templatedir=templates);
}

my $tmp = 't/tmp';
my $statedir = 't/tinypodcast/.ikiwiki';

sub podcast {
	my $podcast_style = shift;

	my $baseurl = 'http://example.com';
	my @command = (@base_command, qw(--plugin inline --rss --atom));
	push @command, "--url=$baseurl", qw(t/tinypodcast), "$tmp/out";

	ok(! system("mkdir $tmp"),
		q{setup});
	ok(! system(@command),
		q{build});

	my %media_types = (
		'simplepost'	=> undef,
		'piano.mp3'	=> 'audio/mpeg',
		'scroll.3gp'	=> 'video/3gpp',
		'walter.ogg'	=> 'audio/ogg',
	);

	for my $format (qw(atom rss)) {
		my $feed = XML::Feed->parse("$tmp/out/$podcast_style/index.$format");

		is($feed->title, $podcast_style,
			qq{$format feed title});
		is($feed->link, "$baseurl/$podcast_style/",
			qq{$format feed link});
		is($feed->description, 'wiki',
			qq{$format feed description});
		if ('atom' eq $format) {
			is($feed->author, $feed->description,
				qq{$format feed author});
			is($feed->id, $feed->link,
				qq{$format feed id});
			is($feed->generator, "ikiwiki",
				qq{$format feed generator});
		}

		for my $entry ($feed->entries) {
			my $title = $entry->title;
			my $url = $entry->id;
			my $body = $entry->content->body;
			my $enclosure = $entry->enclosure;

			is($entry->link, $url, qq{$format $title link});
			isnt($entry->issued, undef,
				qq{$format $title issued date});
			isnt($entry->modified, undef,
				qq{$format $title modified date});

			if (defined $media_types{$title}) {
				is($url, "$baseurl/$title",
					qq{$format $title id});
				is($body, undef,
					qq{$format $title no body text});
				is($enclosure->url, $url,
					qq{$format $title enclosure url});
				is($enclosure->type, $media_types{$title},
					qq{$format $title enclosure type});
				cmp_ok($enclosure->length, '>', 0,
					qq{$format $title enclosure length});
			}
			else {
				# XXX hack hack hack
				my $expected_id = "$baseurl/$title/";
				$expected_id =~ s/\ /_/g;

				is($url, $expected_id,
					qq{$format $title id});
				isnt($body, undef,
					qq{$format $title body text});

				if ('fancy' eq $podcast_style) {
					isnt($enclosure, undef,
						qq{$format $title enclosure});
					my $filename = basename($enclosure->url);
					is($enclosure->type, $media_types{$filename},
						qq{$format $title enclosure type});
					cmp_ok($enclosure->length, '>', 0,
						qq{$format $title enclosure length});
				}
				else {
					is($enclosure, undef,
						qq{$format $title no enclosure});
				}
			}
		}
	}

	ok(! system("rm -rf $tmp $statedir"), q{teardown});
}

sub single_page_html {
	my @command = @base_command;
	push @command, qw(t/tinypodcast), "$tmp/out";

	ok(! system("mkdir $tmp"),
		q{setup});
	ok(! system(@command),
		q{build});

	my $html = "$tmp/out/pianopost/index.html";
	like(_extract_html_content($html, 'content'), qr/has content and/m,
		q{html body text});
	like(_extract_html_content($html, 'enclosure'), qr/Download/m,
		q{html enclosure});
	my ($href) = _extract_html_links($html, 'piano');
	is($href, '/piano.mp3',
		q{html enclosure sans --url is site-absolute});

	$html = "$tmp/out/attempted_multiple_enclosures/index.html";
	like(_extract_html_content($html, 'content'), qr/has content and/m,
		q{html body text});
	like(_extract_html_content($html, 'enclosure'), qr/Download/m,
		q{html enclosure});
	($href) = _extract_html_links($html, 'walter');
	is($href, '/walter.ogg',
		q{html enclosure sans --url is site-absolute});

	my $baseurl = 'http://example.com';
	ok(! system(@command, "--url=$baseurl", q{--rebuild}));

	$html = "$tmp/out/pianopost/index.html";
	($href) = _extract_html_links($html, 'piano');
	is($href, "$baseurl/piano.mp3",
		q{html enclosure with --url is fully absolute});

	$html = "$tmp/out/attempted_multiple_enclosures/index.html";
	($href) = _extract_html_links($html, 'walter');
	is($href, "$baseurl/walter.ogg",
		q{html enclosure with --url is fully absolute});

	ok(! system("rm -rf $tmp $statedir"), q{teardown});
}

sub inlined_pages_html {
	my @command = (@base_command, qw(--plugin inline));
	push @command, qw(t/tinypodcast), "$tmp/out";

	ok(! system("mkdir $tmp"),
		q{setup});
	ok(! system(@command),
		q{build});

	my $html = "$tmp/out/fancy/index.html";
	my $contents = _extract_html_content($html, 'content');
	like($contents, qr/has content and an/m,
		q{html body text from pianopost});
	like($contents, qr/has content and only one/m,
		q{html body text from attempted_multiple_enclosures});
	my $enclosures = _extract_html_content($html, 'inlineenclosure');
	like($enclosures, qr/Download/m,
		q{html enclosure});
	my ($href) = _extract_html_links($html, 'piano.mp3');
	is($href, '/piano.mp3',
		q{html enclosure from pianopost sans --url});
	($href) = _extract_html_links($html, 'walter.ogg');
	is($href, '/walter.ogg',
		q{html enclosure from attempted_multiple_enclosures sans --url});

	ok(! system("rm -rf $tmp $statedir"), q{teardown});
}

sub _extract_html_content {
	my ($file, $desired_id, $desired_tag) = @_;
	$desired_tag = 'div' unless defined $desired_tag;

	my $p = HTML::Parser->new(api_version => 3);
	my $content = '';

	$p->handler(start => sub {
		my ($tag, $self, $attr) = @_;
		return if $tag ne $desired_tag;
		return unless exists $attr->{id} && $attr->{id} eq $desired_id;

		$self->handler(text => sub {
			my ($dtext) = @_;
			$content .= $dtext;
		}, "dtext");
	}, "tagname,self,attr");

	$p->parse_file($file) || die $!;

	return $content;
}

sub _extract_html_links {
	my ($file, $desired_value) = @_;

	my @hrefs = ();

	my $p = HTML::LinkExtor->new(sub {
		my ($tag, %attr) = @_;
		return if $tag ne 'a';
		return unless $attr{href} =~ qr/$desired_value/;
		push(@hrefs, values %attr);
	}, getcwd() . '/' . $file);

	$p->parse_file($file);

	return @hrefs;
}

podcast('simple');
single_page_html();
inlined_pages_html();
podcast('fancy');
