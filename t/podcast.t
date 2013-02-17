#!/usr/bin/perl
use warnings;
use strict;

BEGIN {
	eval q{use XML::Feed};
	if ($@) {
		eval q{use Test::More skip_all => "XML::Feed not available"};
	}
	else {
		eval q{use Test::More tests => 72};
	}
}

sub simple_podcast {
	my $baseurl = 'http://example.com';
	my @command = (qw(./ikiwiki.out -plugin inline -rss -atom));
	push @command, qw(-underlaydir=underlays/basewiki);
	push @command, qw(-set underlaydirbase=underlays -templatedir=templates);
	push @command, "-url=$baseurl", qw(t/tinypodcast t/tmp/out);

	ok(! system("mkdir t/tmp"));
	ok(! system(@command));

	my %media_types = (
		'post'		=> undef,
		'piano.mp3'	=> 'audio/mpeg',
		'scroll.3gp'	=> 'video/3gpp',
		'walter.ogg'	=> 'video/x-theora+ogg',
	);

	for my $format (qw(atom rss)) {
		my $feed = XML::Feed->parse("t/tmp/out/index.$format");

		is($feed->title, 'wiki',
			qq{$format feed title});
		is($feed->link, "$baseurl/",
			qq{$format feed link});
		is($feed->description, $feed->title,
			qq{$format feed description});
		if ('atom' eq $format) {
			is($feed->author, $feed->title,
				qq{$format feed author});
			is($feed->id, "$baseurl/",
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
				is($url, "$baseurl/$title/",
					qq{$format $title id});
				isnt($body, undef,
					qq{$format $title body text});
				is($enclosure, undef,
					qq{$format $title no enclosure});
			}
		}
	}

	ok(! system("rm -rf t/tmp t/tinypodcast/.ikiwiki"));
}

simple_podcast();
