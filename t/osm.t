#!/usr/bin/perl
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

plan(tests => 45);

my $tmp = 't/tmp';
my $srcdir = "$tmp/in";
my $destdir = "$tmp/out";

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
# Test lat/lon parsing.

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

sub call {
	my $fail = shift;
	my $msg = shift;
	my $func = shift;
	my $ret = eval {
		IkiWiki::Plugin::osm::->can($func)->(@_);
	};
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

%pagestate = ();
call_ok('dedup id', preprocess_waypoint => %args);
call_ok('dedup id', preprocess_waypoint => %args);
my @keys = sort keys %{$pagestate{'test'}{OSM}{'map'}{'waypoints'}};
is("@keys", 'test test_1', 'dedup id');

call_ok('dedup divname', preprocess_osm => %args);
call_ok('dedup divname', preprocess_osm => %args);
my @keys = sort keys %{$pagestate{'test'}{OSM}{'map'}{'displays'}};
is("@keys", 'map map_1', 'dedup divname');

1;
