#!/usr/bin/perl
# vim:ts=8:sts=8:sw=8:noet
# Copyright 2018 Martín Ferrari
# Released under GPL version 2

package IkiWiki;

use utf8;
use strict;
use warnings;

use Cwd qw(getcwd);
use IkiWiki;
use Test::More;

eval { require JSON; };
if ($@) {
	plan(skip_all => "JSON module not installed");
}
eval { require IkiWiki::Plugin::osm; };
if ($@) {
	plan(skip_all => "Can't load osm plugin: $@");
}

plan(tests => 65);

my $tmp = 't/tmp';
my $srcdir = "$tmp/in";
my $destdir = "$tmp/out";

my $installed = $ENV{INSTALLED_TESTS};

my @command;
if ($installed) {
	@command = qw(ikiwiki);
}
else {
	ok(! system("make -s ikiwiki.out"));
	@command = ("perl", "-I" . getcwd(), qw(
		./ikiwiki.out
		--underlaydir=underlays/basewiki
		--set underlaydirbase=underlays
		--templatedir=templates));
}

push @command, qw(--plugin osm);
push @command, $srcdir, $destdir;

$IkiWiki::config{srcdir} = $srcdir;
$IkiWiki::config{destdir} = $destdir;
$IkiWiki::config{underlaydir} = "underlays/basewiki";
$IkiWiki::config{templatedir} = 'templates';
$IkiWiki::config{usedirs} = 1;
$IkiWiki::config{htmlext} = 'html';
$IkiWiki::config{wiki_file_chars} = "-[:alnum:]+/.:_";
$IkiWiki::config{userdir} = "users";
$IkiWiki::config{tagbase} = "tags";
$IkiWiki::config{tag_autocreate} = 1;
$IkiWiki::config{tag_autocreate_commit} = 0;
$IkiWiki::config{default_pageext} = "mdwn";
$IkiWiki::config{wiki_file_prune_regexps} = [qr/^\./];
$IkiWiki::config{underlaydirbase} = 'underlays';

IkiWiki::Plugin::osm::import();
is(checkconfig(), 1);

sub check_scrub_lonlat($$$$$*) {
	my ($loc, $lat, $lon, $exp_lat, $exp_lon, $msg) = @_;
	my ($ret_lon, $ret_lat) = eval {
		IkiWiki::Plugin::osm::scrub_lonlat($loc, $lon, $lat);
	};
	if($@) {
		chomp($@);
		ok(0, "Error: $@");
	} else {
		ok(abs($exp_lat - $ret_lat) < 0.001 &&
			abs($exp_lon - $ret_lon) < 0.001,
			"$msg: ($ret_lat, $ret_lon) != ($exp_lat, $exp_lon)");
	}
}

sub check_loc($$$) {
	my ($loc, $exp_lat, $exp_lon) = @_;
	check_scrub_lonlat($loc, undef, undef, $exp_lat, $exp_lon,
		"decode '$loc'");
}

sub check_lon($$) {
	my ($lon, $exp_lon) = @_;
	check_scrub_lonlat(undef, "0", $lon, 0, $exp_lon, "decode '$lon'");
}

sub check_lat($$) {
	my ($lat, $exp_lat) = @_;
	check_scrub_lonlat(undef, $lat, "0", $exp_lat, 0, "decode '$lat'");
}

sub call {
	my($fail, $msg, $func, @args) = @_;
	# Force list contest for full processing.
	my @ret = eval {
		IkiWiki::Plugin::osm::->can($func)->(@args);
	};
	if($fail) {
		ok($@, $msg);
	} else {
		print STDERR $@ if($@);
		ok(! $@, $msg);
	}
	return $ret[0];
}
sub call_ok ($$@) {
	return call(0, @_);
}
sub call_nook ($@) {
	return call(1, @_);
}
sub call_cmp($$$@) {
	my ($msg, $expected, $func, @args) = @_;
	my $out = call_ok($msg, $func, @args);
	like($out, $expected, $msg);
	return $out;
}

# Make sure temp directory is clean.
ok(! system("rm -rf $tmp"), q(Clean temp dir));

# Test lat/lon parsing.

check_lat(q{40 N}, 40);
check_lat(q{40 26 N}, 40.433);
check_lat(q{40 26 46 N}, 40.446);

check_lon(q{79 W}, -79);
check_lon(q{79 58 W}, -79.966);
check_lon(q{79 58 56 W}, -79.982);

check_loc(q{40 N 79 W}, 40, -79);
check_loc(q{40 26 N 79 58 W}, 40.433, -79.966);
check_loc(q{40 26 46 N 79 58 56 W}, 40.446, -79.982);

check_lat(q{40}, 40);
check_lat(q{40 26}, 40.433);
check_lat(q{40 26 46}, 40.446);

check_lon(q{-79}, -79);
check_lon(q{-79 58}, -79.966);
check_lon(q{-79 58 56}, -79.982);

check_loc(q{40, -79}, 40, -79);
check_loc(q{40 26; -79 58}, 40.433, -79.966);
check_loc(q{40 26 46 -79 58 56}, 40.446, -79.982);

check_lat(q{40°}, 40);
check_lat(q{40° 26' N}, 40.433);
check_lat(q{40° 26' 46" N}, 40.446);

check_lon(q{79° W}, -79);
check_lon(q{79° 58' W}, -79.966);
check_lon(q{79° 58' 56" W}, -79.982);

check_loc(q{40° N 79° W}, 40, -79);
check_loc(q{40° 26' N 79° 58' W}, 40.433, -79.966);
check_loc(q{40° 26' 46" N 79° 58' 56" W}, 40.446, -79.982);

check_loc(q{41°24'12.2"N 2°10'26.5"E}, 41.403, 2.174);
check_loc(q{41 24.2028, 2 10.4418}, 41.403, 2.174);
check_loc(q{41.40338, 2.17403}, 41.403, 2.174);

# Parameter validation.

%pagestate = ();

my %args = (page => 'test', destpage => 'test');
call_nook('invalid map name', preprocess_waypoint => %args, map => '43');
call_nook('invalid map name', preprocess_waypoint => %args, map => 'bad-name');
call_nook('invalid id', preprocess_osm => %args, map => '43');
call_nook('invalid id', preprocess_osm => %args, map => 'bad-name');

# Repeated id.
%args = (%args, loc => '40, -79');
call_ok('repeated id', preprocess_waypoint => %args, id => 'waypoint');
call_nook('repeated id', preprocess_waypoint => %args, id => 'waypoint');

call_ok('repeated divname', preprocess_osm => %args, divname => 'div');
call_nook('repeated divname', preprocess_osm => %args, divname => 'div');

# Deduplication of default values.
my @keys;
%pagestate = ();
call_ok('dedup id', preprocess_waypoint => %args);
call_ok('dedup id', preprocess_waypoint => %args);
@keys = sort keys %{$pagestate{'test'}{OSM}{'map'}{'waypoints'}};
is("@keys", 'test test_1', 'dedup id');

call_ok('dedup divname', preprocess_osm => %args);
call_ok('dedup divname', preprocess_osm => %args);
@keys = sort keys %{$pagestate{'test'}{OSM}{'map'}{'displays'}};
is("@keys", 'map map_1', 'dedup divname');

# Directive output.
%args = (page => 'test', destpage => 'test', map => 'foo', height => '400px');
my $mapdiv_re = (
	qr(^\Q<div id="mapdiv-foo" style="height: 400px" class="osm">\Q)m .
	qr(\Q</div>\E\n));
my $geojson_re = (
	qr(^\Q<script src="../ikiwiki/osm/foo.js" type="text/javascript" \E)m .
	qr(\Qcharset="utf-8"></script>\E\n));
my $displaymap_re = (qr(
	<script\ type="text/javascript">\n
	display_map\('mapdiv-foo',\ geojson_foo,\ \{.*\}\);\n
	</script>$
	)mx);
my $expected = qr($mapdiv_re$geojson_re$displaymap_re);

call_cmp('[[!waypoint]] does not render output', qr(^$),
	preprocess_waypoint => (%args, loc => '40, -79'));

%pagestate = (); %IkiWiki::Plugin::osm::json_embedded = ();
call_cmp('[[!waypoint embed]] rendering', $expected,
	preprocess_waypoint => (%args, loc => '40, -79', embed => ''));

%pagestate = (); %IkiWiki::Plugin::osm::json_embedded = ();
call_cmp('[[!osm]] rendering', $expected, preprocess_osm => %args);

# Test end-to-end generation of files.
my $page1 = <<END;
[[!waypoint map=foo embed loc=53.3430824,-6.2701176]]
[[!waypoint map=bar loc=53.3469584,-6.2723297]]
[[page2]]
END
my $page2 = <<END;
[[!waypoint map=foo name=myname loc=53.3509340,-6.2700980]]
[[!waypoint map=foo id=foowp desc=desc loc=53.3424332,-6.2944638]]
[[!osm map=baz]]
END

ok(! system("mkdir -p $srcdir"), q(setup));
writefile("page1.mdwn", $srcdir, $page1);
writefile("page2.mdwn", $srcdir, $page2);
ok(! system(@command), q(build));

my $page1out = readfile("$destdir/page1/index.html");
my $page2out = readfile("$destdir/page2/index.html");

like($page1out, qr(^<link rel="stylesheet" href=".*/leaflet.css")m,
	'Include leaflet CSS in output');
like($page1out, qr(^<script src=".*/leaflet.js" type="text/javascript")m,
	'Include leaflet JS in output');

ok(-f "$destdir/ikiwiki/osm/foo.js", 'GeoJSON file created');
my $foojson = readfile("$destdir/ikiwiki/osm/foo.js");
like($foojson, qr(^var geojson_foo = ), 'GeoJSON syntax');
$foojson =~ s(^var geojson_foo = )();

my $fooexpected = {
	'type' => 'FeatureCollection',
	'features' => [
		{
			'type' => 'Feature',
			'geometry' => {
				'type' => 'Point',
				'coordinates' => ['-6.2701176', '53.3430824'],
			},
			'properties' => {
				'id' => 'page1', 'name' => 'page1',
				'desc' => '', 'href' => '/page1/',
				'lat' => '53.3430824', 'lon' => '-6.2701176',
			},
		},
		{
			'type' => 'Feature',
			'geometry' => {
				'type' => 'Point',
				'coordinates' => ['-6.2944638', '53.3424332'],
			},
			'properties' => {
				'id' => 'foowp', 'name' => 'page2',
				'desc' => 'desc', 'href' => '/page2/',
				'lat' => '53.3424332', 'lon' => '-6.2944638',
			},
		},
		{
			'type' => 'Feature',
			'geometry' => {
				'type' => 'Point',
				'coordinates' => ['-6.270098', '53.350934'],
			},
			'properties' => {
				'id' => 'page2', 'name' => 'myname',
				'desc' => '', 'href' => '/page2/',
				'lat' => '53.350934', 'lon' => '-6.270098',
			},
		},
		{
			'type' => 'Feature',
			'geometry' => {
				'type' => 'LineString',
				'coordinates' => [
					['-6.2701176', '53.3430824'],
					['-6.2944638', '53.3424332'],
				],
			},
		},
		{
			'type' => 'Feature',
			'geometry' => {
				'type' => 'LineString',
				'coordinates' => [
					['-6.2701176', '53.3430824'],
					['-6.270098', '53.350934'],
				],
			},
		},
	],
};

is_deeply(JSON::decode_json($foojson), $fooexpected,
	'Verify GeoJSON structure');

ok(-f "$destdir/ikiwiki/osm/bar.js", 'GeoJSON file created');
my $barjson = readfile("$destdir/ikiwiki/osm/bar.js");
like($barjson, qr(^var geojson_bar = ), 'GeoJSON syntax');
$barjson =~ s(^var geojson_bar = )();

my $barexpected = {
	'type' => 'FeatureCollection',
	'features' => [
		{
			'type' => 'Feature',
			'geometry' => {
				'type' => 'Point',
				'coordinates' => ['-6.2723297', '53.3469584'],
			},
			'properties' => {
				'id' => 'page1', 'name' => 'page1',
				'desc' => '', 'href' => '/page1/',
				'lat' => '53.3469584', 'lon' => '-6.2723297',
			},
		},
	],
};
is_deeply(JSON::decode_json($barjson), $barexpected,
	'Verify GeoJSON structure');

ok(! system("rm -rf $tmp"), q(teardown));

1;
