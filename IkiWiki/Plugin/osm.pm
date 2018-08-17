#!/usr/bin/perl
# vim:ts=8:sts=8:sw=8:noet
# Copyright 2018 Martín Ferrari
# Copyright 2011 Blars Blarson
# Released under GPL version 2

package IkiWiki::Plugin::osm;

use utf8;
use strict;
use warnings;

use IkiWiki 3.0;
use JSON;

use constant OSM => "osm";
use constant OUTPUT_PATH => "/ikiwiki/" . OSM;
use constant JS_IDENTIFIER_RE => qr/^[a-zA-Z_][0-9a-zA-Z_]*$/o;
use constant DMS_RE => qr/
	(\d+(?:\.\d*)?)[\s°]?           # Degrees
	(?:\s*(\d+(?:\.\d*)?)[\s`´']?   # Minutes
	  (?:\s*(\d+(?:\.\d*)?)[\s"]?)? # Seconds
	)?
	/xo;

sub import {
	add_underlay(OSM);
	hook(type => "getsetup", id => OSM, call => \&getsetup);
	hook(type => "checkconfig", id => OSM, call => \&checkconfig);
	hook(type => "needsbuild", id => OSM, call => \&needsbuild);
	hook(type => "preprocess", id => "osm", call => \&preprocess_osm);
	hook(type => "preprocess", id => "waypoint", scan => 1,
		call => \&preprocess_waypoint);
	hook(type => "format", id => OSM, call => \&format);
	hook(type => "changes", id => OSM, call => \&changes);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 1,
			section => "special-purpose",
		},
		osm_default_zoom => {
			type => "integer",
			example => "15",
			description => "default map zoom",
			safe => 1,
			rebuild => 1,
		},
		osm_leafletjs_url => {
			type => "string",
			example =>
			"https://unpkg.com/leaflet@1.3.1/dist/leaflet.js",
			description => "Url for the leaflet.js file",
			safe => 0,
			rebuild => 1,
		},
		osm_leafletcss_url => {
			type => "string",
			example =>
			"https://unpkg.com/leaflet@1.3.1/dist/leaflet.css",
			description => "Url for the leaflet.css file",
			safe => 0,
			rebuild => 1,
		},
		osm_tile_source => {
			type => "string",
			example =>
			"https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
			description => "URL pattern for tile layers. " +
			"See Leaflet documentation for tileLayer.",
			safe => 0,
			rebuild => 1,
		},
		osm_attribution => {
			type => "string",
			example =>
			q(&copy; <a href="http://osm.org/copyright">) +
			q(OpenStreetMap</a> contributors),
			description => "Text describing the tile source.",
			safe => 0,
			rebuild => 1,
		};
}

sub checkconfig {
	$config{'osm_default_zoom'} = 15
		unless (defined $config{'osm_default_zoom'});
	$config{'osm_leafletjs_url'} =
	"https://unpkg.com/leaflet@1.3.1/dist/leaflet.js"
		unless (defined $config{'osm_leafletjs_url'});
	$config{'osm_leafletcss_url'} =
	"https://unpkg.com/leaflet@1.3.1/dist/leaflet.css"
		unless (defined $config{'osm_leafletcss_url'});
	$config{'osm_tile_source'} =
	"https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
		unless (defined $config{'osm_tile_source'});
	$config{'osm_attribution'} = q(&copy; <a
	href="http://osm.org/copyright">OpenStreetMap</a> contributors)
		unless (defined $config{'osm_attribution'});
}

# Index for ensuring waypoints have unique IDs.
my %waypointidx = ();

# Idea taken from meta.pm plugin.
# Make sure cached state is cleaned before rebuilding (and after deleting)
# pages.
sub needsbuild {
	my $needsbuild = shift;
	my $deleted = shift;
	my %touched = map { $_ => 1 } (@$needsbuild, @$deleted);
	foreach my $page (keys %pagestate) {
		next unless (exists $pagestate{$page}{OSM} and
			exists $pagesources{$page});
		if (exists $touched{$pagesources{$page}}) {
			delete $pagestate{$page}{OSM};
		}
		# Rebuild index.
		foreach my $map (keys %{$pagestate{$page}{OSM}}) {
			my $wps = $pagestate{$page}{OSM}{$map}{'waypoints'};
			foreach my $wp (keys %$wps) {
				$waypointidx{$map}{$wp} = $wps->{$wp};
			}
		}
	}
	return $needsbuild;
}

sub preprocess_osm {
	my %params = @_;
	my $page = $params{'page'};
	my $dest = $params{'destpage'};

	my $map = $params{'map'} || 'map';
	my $height = scrub($params{'height'} || '300px', $page, $dest);
	my $width = scrub($params{'width'} || '500px', $page, $dest);
	my $float = (defined($params{'right'}) && 'right') || (
		defined($params{'left'}) && 'left');

	my $showlines = defined($params{'showlines'});
	my $nolinkpages = defined($params{'nolinkpages'});
	my $highlight = $params{'highlight'} || '';

	my $loc = $params{'loc'};
	my $lat = $params{'lat'};
	my $lon = $params{'lon'};
	my $zoom = $params{'zoom'} // $config{'osm_default_zoom'};
	($lon, $lat) = scrub_lonlat($loc, $lon, $lat);

	error(sprintf(gettext("Invalid map name: %s"), $map)) if (
		$map !~ JS_IDENTIFIER_RE);
	error(sprintf(gettext("Invalid zoom: %s"), $zoom)) if (
		$zoom !~ /^\d\d?$/ || $zoom < 2 || $zoom > 18);

	will_render($page, OUTPUT_PATH . "/${map}.js");
	return unless defined wantarray;  # Scan mode.

	# Make sure the div ID is unique in this (dest) page.
	my $div_id = generate_unique_key(
		$pagestate{$dest}{OSM}{$map}{'displays'}, "map-$map");

	# Register this page is rendering map $map inside div $id.
	my $map_opts = $pagestate{$dest}{OSM}{$map}{'displays'}{$div_id} = {
		height => $height,
		width => $width,
		float => $float,
		showlines => $showlines || 0,
		nolinkpages => $nolinkpages || 0,
		highlight => $highlight,
		zoom => $zoom,
	};
	if (defined $lat and defined $lon) {
		$map_opts->{'lat'} = $lat;
		$map_opts->{'lon'} = $lon;
	}
	# Place a <div> shiv that is filled with parameters later.
	return qq(<div id="$div_id" class="osm"></div>\n);
}

our $waypoint_changed = 0;

sub preprocess_waypoint {
	my %params = @_;
	my $page = $params{'page'};
	my $dest = $params{'destpage'};
	my $preview = $params{'preview'};
	my $p = IkiWiki::basename($page);

	my $map = $params{'map'} || 'map';
	my $id = $params{'id'};
	my $name = scrub($params{'name'} || pagetitle($p), $page, $dest);
	my $desc = scrub($params{'desc'} || '', $page, $dest);

	my $embed = defined($params{'embed'});
	# Passed verbatim to preprocess_osm.
	my $height = $params{'height'};
	my $width = $params{'width'};
	my $right = $params{'right'};
	my $left = $params{'left'};
	my $showlines = $params{'showlines'};
	my $nolinkpages = $params{'nolinkpages'};

	my $loc = $params{'loc'};
	my $lat = $params{'lat'};
	my $lon = $params{'lon'};
	my $zoom = $params{'zoom'} // $config{'osm_default_zoom'};
	($lon, $lat) = scrub_lonlat($loc, $lon, $lat);

	error(sprintf(gettext("Invalid map name: %s"), $map)) if (
		$map !~ JS_IDENTIFIER_RE);
	error(sprintf(gettext("Duplicate waypoint id: %s"), $id)) if (
		$id and exists $waypointidx{$map}{$id});
	error(gettext("Must specify lat and lon (or loc)")) unless (
		defined $lat and defined $lon);
	error(sprintf(gettext("Invalid zoom: %s"), $zoom)) if (
		$zoom !~ /^\d\d?$/ || $zoom < 2 || $zoom > 18);

	# Register json file that will be rendered.
	will_render($page, OUTPUT_PATH . "/${map}.js");

	return unless defined wantarray;  # Scan mode.

	$waypointidx{$map} ||= {};
	$id = generate_unique_key($waypointidx{$map}, $page) unless($id);

	# Do not create waypoints from inlined or preview pages; and only
	# during scan mode.
	if ($page eq $dest and not $preview) {
		$waypoint_changed = 1;
		debug(sprintf(gettext("osm: found waypoint %s/%s"),
				$map, $id));
		$waypointidx{$map}{$id} =
		$pagestate{$page}{OSM}{$map}{'waypoints'}{$id} = {
			id => $id,
			name => $name,
			desc => $desc,
			lat => $lat,
			lon => $lon,
			page => $page,
			# How to link back to the page from the map, must be
			# absolute.
			href => urlto($page),
		};
	}

	my $output = '';
	if ($embed) {
		$output .= preprocess_osm(
			page => $page,
			destpage => $dest,
			map => $map,
			height => $height,
			width => $width,
			right => $right,
			left => $left,
			showlines => $showlines,
			nolinkpages => $nolinkpages,
			lat => $lat,
			lon => $lon,
			zoom => $zoom,
			highlight => $id,
		);
	}
	return $output;
}

# Given a HASH ref and an initial key, iterate until key is unique in that
# HASH.
sub generate_unique_key($$) {
	my ($hashref, $initial_key) = @_;

	my $num = 1;
	my $id = $initial_key;
	while (exists $hashref->{$id}) {
		$id = "${initial_key}_${num}";
		$num++;
	}
	return $id;
}

sub scrub_lonlat($$$) {
	my ($loc, $lon, $lat) = @_;
	my $lat_re = qr/([+-]?)/ . DMS_RE . qr/\s*([ns]?)/i;
	my $lon_re = qr/([+-]?)/ . DMS_RE . qr/\s*([ew]?)/i;
	if ($loc) {
		if ($loc =~ /
			^\s*
			($lat_re)
			\s*[,;\s]\s*
			($lon_re)
			\s*$
			/x
		) {
			$lat = $1;
			$lon = $7;
		}
		else {
			error(sprintf(gettext(
				"Bad value for loc parameter: %s"), $loc));
		}
	}
	if (defined($lat)) {
		if ($lat =~ /^\s*$lat_re\s*$/) {
			$lat = $2 + ($3 // 0) / 60 + ($4 // 0) / 3600;
			if ($1 eq '-' or uc($5 // '') eq 'S') {
				$lat = - $lat;
			}
		}
		else {
			error(sprintf(gettext(
				"Bad value for lat parameter: %s"), $lat));
		}
	}
	if (defined($lon)) {
		if ($lon =~ /^\s*$lon_re\s*$/) {
			$lon = $2 + ($3 // 0) / 60 + ($4 // 0) / 3600;
			if ($1 eq '-' or uc($5 // '') eq 'W') {
				$lon = - $lon;
			}
		}
		else {
			error(sprintf(gettext(
				"Bad value for lon parameter: %s"), $lon));
		}
	}
	if (!defined($lon) || !defined($lat)) {
		return (undef, undef);
	}
	if ($lat < -90 || $lat > 90 || $lon < -180 || $lon > 180) {
		error(sprintf(gettext("Location out of range: (%s, %s)"),
			$lat, $lon));
	}
	return ($lon + 0.0, $lat + 0.0);
}

sub find_waypoints() {
	my %waypoints = ();
	foreach my $page (keys %pagestate) {
		next unless (exists $pagestate{$page}{OSM});
		my $maps = $pagestate{$page}{OSM};
		foreach my $map (keys %$maps) {
			# Make sure a GeoJSON file is generated even if empty.
			$waypoints{$map} ||= {};
			next unless (exists $maps->{$map}{'waypoints'} and
				$maps->{$map}{'waypoints'});
			$waypoints{$map}{$page} = $maps->{$map}{'waypoints'};
		}
	}
	return \%waypoints;
}

sub find_wplines($) {
	# Draw lines between waypoints whose pages link each other.
	my $mapwps = shift;
	my @lines;
	foreach my $page (sort keys %{$mapwps}) {
		next unless (exists $links{$page});
		foreach my $otherpage (@{$links{$page}}) {
			my $bestlink = bestlink($page, $otherpage);
			next unless (exists $mapwps->{$bestlink});
			foreach my $wpid (sort keys %{$mapwps->{$page}}) {
				my $wp = $mapwps->{$page}{$wpid};
				foreach my $otherwpid (
					sort keys %{$mapwps->{$bestlink}}
				) {
					my $otherwp =
						$mapwps->{$bestlink}{$otherwpid};
					push(@lines, [$wp, $otherwp]);
				}
			}
		}
	}
	return \@lines;
}

sub changes {
	return unless($waypoint_changed);
	my $waypoints = find_waypoints();
	my %lines = ();
	foreach my $map (keys %$waypoints) {
		$lines{$map} = find_wplines($waypoints->{$map});
	}
	writejson($waypoints, \%lines);
	$waypoint_changed = 0;
}

sub writejson($;$) {
	my %waypoints = %{$_[0]};
	my %lines = %{$_[1]};

	foreach my $map (keys %waypoints) {
		my %geojson = (
			"type" => "FeatureCollection",
			"features" => [],
		);
		foreach my $page (sort keys %{$waypoints{$map}}) {
			foreach my $wpid (sort keys %{$waypoints{$map}{$page}}
			) {
				my $wp = $waypoints{$map}{$page}{$wpid};
				my %marker = (
					"type" => "Feature",
					"geometry" => {
						"type" => "Point",
						"coordinates" => [
							$wp->{'lon'} + 0.0,
							$wp->{'lat'} + 0.0,
						],
					},
					"properties" => $wp,
				);
				push @{$geojson{'features'}}, \%marker;
			}
		}
		foreach my $lines (@{$lines{$map}}) {
			my $coord = [
				[
					$lines->[0]->{'lon'} + 0.0,
					$lines->[0]->{'lat'} + 0.0,
				],
				[
					$lines->[1]->{'lon'} + 0.0,
					$lines->[1]->{'lat'} + 0.0,
				]
			];
			my %json  = (
				"type" => "Feature",
				"geometry" => {
					"type" => "LineString",
					"coordinates" => $coord,
				},
			);
			push @{$geojson{'features'}}, \%json;
		}
		debug(sprintf(gettext("osm: building %s"),
                        OUTPUT_PATH .  "/$map.js"));
		writefile("$map.js", "$config{'destdir'}/" . OUTPUT_PATH,
			"var geojson_$map = " . to_json(\%geojson));
	}
}

# pipe some data through the HTML scrubber
#
# code taken from the meta.pm plugin
sub scrub($$$) {
	if (IkiWiki::Plugin::htmlscrubber->can('sanitize')) {
		return IkiWiki::Plugin::htmlscrubber::sanitize(
			content => shift, page => shift, destpage => shift);
	}
	else {
		return shift;
	}
}

sub format (@) {
	my %params = @_;
	my $page = $params{'page'};
	my $content = $params{'content'};

	return $content unless (
		exists $pagestate{$page}{OSM} and
		grep { exists $_->{'displays'} }
		values(%{$pagestate{$page}{OSM}})
	);

	# Fill map <div> with attributes and javascript code.
	# Needs to be done here, so htmlscrubber does not remove the tags.
	my @maps_present = ();
	foreach my $map (keys %{$pagestate{$page}{OSM}}) {
		my $displays = $pagestate{$page}{OSM}{$map}{'displays'};
		next unless($displays and %$displays);
		foreach my $div_id (keys %$displays) {
			my $map_opts = $displays->{$div_id};
			my $height = $map_opts->{'height'};
			my $orig = qq(<div id="$div_id" class="osm"></div>\n);
			my $repl = (qq(<div id="$div_id" class="osm" ) .
				qq(style="height: $height"></div>\n));
			$repl .= display_map_js($map, $div_id, %$map_opts);
			$content =~ s(\Q$orig\E)($repl);
		}
		push @maps_present, $map;
	}

	# Add Leaflet setup code and load GeoJSON files.
	my $js = map_setup_js($page);
	foreach my $map (@maps_present) {
		$js .= load_geojson_js($map, $page);
	}
	my ($before, $after) = split(m(</head>), $content, 2);
	if (defined $after) {
		return $before . $js . '</head>' . $after;
	}
	return $js . $content;
}

sub map_setup_js($) {
	my $page = shift;

	my $cssurl = $config{'osm_leafletcss_url'};
	my $olurl = $config{'osm_leafletjs_url'};
	my $displaymap_link = bestlink($page, OUTPUT_PATH . "/display_map.js");
	my $displaymap_url = urlto($displaymap_link, $page);

	return <<END;
<link href="$cssurl"
 rel="stylesheet" crossorigin=""/>
<script src="$olurl"
 type="text/javascript" crossorigin="" charset="utf-8"></script>
<script src="$displaymap_url"
 type="text/javascript" charset="utf-8"></script>
END
}

our %json_embedded;

sub load_geojson_js($$) {
	my $map = shift;
	my $dest = shift;

	return '' if ($json_embedded{$dest}{$map});
	$json_embedded{$dest}{$map} = 1;

	my $jsonurl = urlto(OUTPUT_PATH . "/${map}.js", $dest);
	my $ret = qq(<script src="$jsonurl" type="text/javascript");
	$ret .= qq( charset="utf-8"></script>\n);
	return $ret;
}

sub display_map_js($$;@) {
	my $map = shift;
	my $div_id = shift;
	my %options = @_;

	$options{'tilesrc'} = $config{'osm_tile_source'};
	$options{'attribution'} = $config{'osm_attribution'};

	my $ret = qq(<script type="text/javascript">\n);
	$ret .= qq{display_map('$div_id', geojson_$map, };
	$ret .= to_json(\%options);
	$ret .= qq{);\n</script>\n};
	return $ret;
}

1;
