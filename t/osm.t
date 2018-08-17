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

plan(tests => 82);

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
	my $ret;
	if (defined wantarray) {
		$ret = eval {
			IkiWiki::Plugin::osm::->can($func)->(@args);
		};
	} else {
		eval {
			IkiWiki::Plugin::osm::->can($func)->(@args);
		};
	}
	if($fail) {
		ok($@, $msg);
	} else {
		print STDERR $@ if($@);
		ok(! $@, $msg);
	}
	return $ret;
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

# Deduplication of default values.
%pagestate = ();
call_ok('dedup id', preprocess_waypoint => %args);
call_ok('dedup id', preprocess_waypoint => %args);
is_deeply([sort keys %{$pagestate{'test'}{OSM}{'map'}{'waypoints'}}],
	[qw(test test_1)], 'dedup id');

my $ctx;  # Force non-scan mode.
$ctx = call_ok('dedup div id', preprocess_osm => %args);
$ctx = call_ok('dedup div id', preprocess_osm => %args);
is_deeply([sort keys %{$pagestate{'test'}{OSM}{'map'}{'displays'}}],
	[qw(map-map map-map_1)], 'dedup div id');

# Directive output.
%args = (page => 'test', destpage => 'test', map => 'foo',
	height => '400px');
my $mapdiv = qr(<div id="map-foo" class="osm"></div>\n);

call_cmp('[[!waypoint]] does not render output', qr(^$),
	preprocess_waypoint => (%args, loc => '40, -79'));

%pagestate = (); %IkiWiki::Plugin::osm::json_embedded = ();
call_cmp('[[!waypoint embed]] rendering', $mapdiv,
	preprocess_waypoint => (%args, loc => '40, -79', embed => ''));

%pagestate = (); %IkiWiki::Plugin::osm::json_embedded = ();
call_cmp('[[!osm]] rendering', $mapdiv, preprocess_osm => %args);

# Test end-to-end generation of files.
my $page1 = <<END;
[[!waypoint map=foo embed loc=53.3430824,-6.2701176]]
[[!waypoint map=bar loc=53.3469584,-6.2723297]]
[[page2]]
END
my $page2 = <<END;
[[!waypoint map=foo name=myname loc=53.3509340,-6.2700980]]
[[!waypoint map=foo id=foowp desc=desc loc=53.3424332,-6.2944638]]
[[!osm map=bar]]
[[!osm map=baz]]
END
my $page3 = <<END;
[[!inline pages="page1 or page2"]]
END

ok(! system("rm -rf $tmp"), q(Clean temp dir));
ok(! system("mkdir -p $srcdir"), q(setup));
writefile("page1.mdwn", $srcdir, $page1);
writefile("page2.mdwn", $srcdir, $page2);
writefile("page3.mdwn", $srcdir, $page3);
ok(! system(@command), q(build));

my $page1out = readfile("$destdir/page1/index.html");
my $page2out = readfile("$destdir/page2/index.html");
my $page3out = readfile("$destdir/page3/index.html");

for my $page ($page1out, $page2out, $page3out) {
	like($page, qr(^<link href="[^"]*/leaflet\.css"\s)m,
		'Include leaflet CSS in output');
	like($page, qr(^<script src="[^"].*/leaflet\.js"\s)m,
		'Include leaflet JS in output');
	like($page, qr(^<script src=".*/display_map\.js"\s)m,
		'Include display_map JS in output');
}

my $geojson_resub = sub {
	my $map = shift;
	return qr(
		<script\ src="\.\./ikiwiki/osm/$map\.js"\s+
		type="text/javascript"\ charset="utf-8"></script>\n
		)x;
};
my $displaymap_resub = sub {
	my $map = shift;
	my $pre = qq(<div id="map-$map" class="osm" );
	$pre .= qq(style="height: 300px"></div>\n);
	$pre .= qq(<script type="text/javascript">\n);
	$pre .= qq[display_map('map-$map', geojson_$map, {];
	my $post = qq[});\n</script>\n];
	return qr(\Q$pre\E.*\Q$post\E);
};

like($page1out, $geojson_resub->('foo'), 'Include "foo" GeoJSON in page');
unlike($page1out, $geojson_resub->('bar'), 'Exclude "bar" GeoJSON in page');
like($page1out, $displaymap_resub->('foo'), 'Render "foo" map');

unlike($page2out, $geojson_resub->('foo'), 'Exclude "foo" GeoJSON in page');
like($page2out, $geojson_resub->('bar'), 'Include "bar" GeoJSON in page');
like($page2out, $geojson_resub->('baz'), 'Include "baz" GeoJSON in page');
like($page2out, $displaymap_resub->('bar'), 'Render "bar" map');
like($page2out, $displaymap_resub->('baz'), 'Render "baz" map');

like($page3out, $displaymap_resub->('foo'), 'Render "foo" map');

my %json_expected;
$json_expected{foo} = {
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
$json_expected{bar} = {
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
$json_expected{baz} = {
	'type' => 'FeatureCollection',
	'features' => [],
};

for my $map (qw(foo bar baz)) {
	ok(-f "$destdir/ikiwiki/osm/$map.js",
		qq(GeoJSON file "$map.js" created));
	my $json = readfile("$destdir/ikiwiki/osm/$map.js");
	like($json, qr(^var geojson_$map = ), 'GeoJSON syntax');
	$json =~ s(^var geojson_$map = )();
	is_deeply(JSON::decode_json($json), $json_expected{$map},
		'Verify GeoJSON structure');
}

ok(! system("rm -rf $tmp"), q(teardown));

1;
