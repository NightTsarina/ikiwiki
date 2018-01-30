#!/usr/bin/perl
# Copyright 2011 Blars Blarson
# Released under GPL version 2

package IkiWiki::Plugin::osm;
use utf8;
use strict;
use warnings;
use IkiWiki 3.0;
use JSON;

use constant OSM => "osm";
our $waypoint_changed = 0;

sub import {
	add_underlay(OSM);
	hook(type => "getsetup", id => OSM, call => \&getsetup);
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
			example => "https://unpkg.com/leaflet@1.3.1/dist/leaflet.js",
			description => "Url for the leaflet.js file",
			safe => 0,
			rebuild => 1,
		},
		osm_leafletcss_url => {
			type => "string",
			example => "https://unpkg.com/leaflet@1.3.1/dist/leaflet.css",
			description => "Url for the leaflet.css file",
			safe => 0,
			rebuild => 1,
		},
		osm_tile_source => {
			type => "string",
			example => "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
			description => "URL pattern for tile layers. See Leaflet documentation for tileLayer.",
			safe => 0,
			rebuild => 1,
		},
		osm_attribution => {
			type => "string",
			example => q(&copy; <a href="http://osm.org/copyright">OpenStreetMap</a> contributors),
			description => "Text describing the tile source.",
			safe => 0,
			rebuild => 1,
		};
}

sub register_rendered_files {
	my $map = shift;
	my $page = shift;
	my $dest = shift;

	if ($page eq $dest) {
		will_render($page, "/ikiwiki/" . OSM . "/${map}.js");
	}
}

sub needsbuild {
	my $needsbuild = shift;
	foreach my $page (keys %pagestate) {
		next unless (exists $pagestate{$page}{OSM} and
			exists $pagesources{$page});
		if (grep { $_ eq $pagesources{$page} } @$needsbuild) {
			delete $pagestate{$page}{OSM};
		}
	}
	return $needsbuild;
}


sub preprocess_osm {
	my %params=@_;
	my $page = $params{page};
	my $dest = $params{destpage};

	my $map = $params{'map'} || 'map';
	my $divname = $params{'divname'};
	my $height = scrub($params{'height'} || '300px', $page, $dest);
	my $width = scrub($params{'width'} || '500px', $page, $dest);
	my $float = (defined($params{'right'}) && 'right') || (defined($params{'left'}) && 'left');

	my $showlines = defined($params{'showlines'});
	my $nolinkpages = defined($params{'nolinkpages'});
	my $highlight = $params{'highlight'} || '';

	my $loc = $params{loc};
	my $lat = $params{lat};
	my $lon = $params{lon};
	my $zoom = $params{'zoom'} // $config{'osm_default_zoom'} // 15;

	error("Invalid map name: $map") if ($map !~ /^[\w-]+$/);
	error("Duplicate div name: $divname") if ($divname and
		exists $pagestate{$page}{OSM}{$map}{'displays'}{$divname});
	error("Invalid div name: $divname") if ($divname and
		$divname !~ /^[\w-]+$/);
	error("Invalid zoom: $zoom") if (
		$zoom !~ /^\d\d?$/ || $zoom < 2 || $zoom > 18);

	if (defined($lon) || defined($lat) || defined($loc)) {
		($lon, $lat) = scrub_lonlat($loc, $lon, $lat);
	}
	$divname = $map unless($divname);
	my $num = 1;
	while (exists $pagestate{$page}{OSM}{$map}{'displays'}{$divname}) {
		$divname = "${map}_${num}";
		$num++;
	}
	$pagestate{$page}{OSM}{$map}{'displays'}{$divname} = 1;

	my %map_opts = (
		fullscreen => 0,
		height => $height,
		width => $width,
		float => $float,
		showlines => $showlines || 0,
		nolinkpages => $nolinkpages || 0,
		highlight => $highlight,
		zoom => $zoom,
	);
	if (defined $lat and defined $lon) {
		$map_opts{lat} = $lat;
		$map_opts{lon} = $lon;
	}

	my $ret = qq(<div id="mapdiv-$divname" style="height: $height"></div>\n);
	$ret .= load_geojson_js($map, $dest);
	$ret .= display_map_js($map, $divname, %map_opts);
	return $ret;
}

sub preprocess_waypoint {
	my %params = @_;
	my $page = $params{'page'};
	my $dest = $params{'destpage'};
	my $p = IkiWiki::basename($page);

	my $map = $params{'map'} || 'map';
	my $id = $params{'id'};
	my $name = scrub($params{'name'} || pagetitle($p), $page, $dest);
	my $desc = scrub($params{'desc'} || '', $page, $dest);

	my $embed = defined($params{'embed'});
	# Passed verbatim to preprocess_osm.
	my $divname = $params{'divname'};
	my $height = $params{'height'};
	my $width = $params{'width'};
	my $right = $params{'right'};
	my $left = $params{'left'};
	my $showlines = $params{'showlines'};
	my $nolinkpages = $params{'nolinkpages'};

	my $loc = $params{'loc'};
	my $lat = $params{'lat'};
	my $lon = $params{'lon'};
	my $zoom = $params{'zoom'} // $config{'osm_default_zoom'} // 15;
	($lon, $lat) = scrub_lonlat($loc, $lon, $lat);

	error("Invalid map name: $map") if ($map !~ /^[\w-]+$/);
	error("Duplicate waypoint id: $id") if (
		$id && exists $pagestate{$page}{OSM}{$map}{'waypoints'}{$id});
	error("Must specify lat and lon (or loc)") unless (
		defined $lat && defined $lon);
	error("Invalid zoom: $zoom") if (
		$zoom !~ /^\d\d?$/ || $zoom < 2 || $zoom > 18);

	$id = $page unless($id);
	my $num = 1;
	while (exists $pagestate{$page}{OSM}{$map}{'waypoints'}{$id}) {
		$id = "${page}_${num}";
		$num++;
	}

	register_rendered_files($map, $page, $dest);
	return unless defined wantarray;  # Scan mode.

	$waypoint_changed = 1;
	$pagestate{$page}{OSM}{$map}{'waypoints'}{$id} = {
		id => $id,
		name => $name,
		desc => $desc,
		lat => $lat,
		lon => $lon,
		# How to link back to the page from the map, must be absolute.
		href => urlto($page),
	};
	my $output = '';
	if ($embed) {
		$output .= preprocess_osm(
			page => $page,
			destpage => $dest,
			map => $map,
			divname => $divname,
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

sub scrub_lonlat($$$) {
	my ($loc, $lon, $lat) = @_;
	if ($loc) {
		if ($loc =~ /^\s*(\-?\d+(?:\.\d*°?|(?:°?|\s)\s*\d+(?:\.\d*\'?|(?:\'|\s)\s*\d+(?:\.\d*)?\"?|\'?)°?)[NS]?)\s*\,?\;?\s*(\-?\d+(?:\.\d*°?|(?:°?|\s)\s*\d+(?:\.\d*\'?|(?:\'|\s)\s*\d+(?:\.\d*)?\"?|\'?)°?)[EW]?)\s*$/) {
			$lat = $1;
			$lon = $2;
		}
		else {
			error("Bad loc");
		}
	}
	if (defined($lat)) {
		if ($lat =~ /^(\-?)(\d+)(?:(\.\d*)°?|(?:°|\s)\s*(\d+)(?:(\.\d*)\'?|(?:\'|\s)\s*(\d+(?:\.\d*)?\"?)|\'?)|°?)\s*([NS])?\s*$/) {
			$lat = $2 + ($3//0) + ((($4//0) + (($5//0) + (($6//0)/60.)))/60.);
			if (($1 eq '-') || (($7//'') eq 'S')) {
				$lat = - $lat;
			}
		}
		else {
			error("Bad lat");
		}
	}
	if (defined($lon)) {
		if ($lon =~ /^(\-?)(\d+)(?:(\.\d*)°?|(?:°|\s)\s*(\d+)(?:(\.\d*)\'?|(?:\'|\s)\s*(\d+(?:\.\d*)?\"?)|\'?)|°?)\s*([EW])?$/) {
			$lon = $2 + ($3//0) + ((($4//0) + (($5//0) + (($6//0)/60.)))/60.);
			if (($1 eq '-') || (($7//'') eq 'W')) {
				$lon = - $lon;
			}
		}
		else {
			error("Bad lon");
		}
	}
	if ($lat < -90 || $lat > 90 || $lon < -180 || $lon > 180) {
		error("Location out of range");
	}
	return ($lon + 0.0, $lat + 0.0);
}

sub changes {
	my %waypoints = ();
	my %linestrings = ();

	return unless($waypoint_changed);
	foreach my $page (keys %pagestate) {
		next unless (exists $pagestate{$page}{OSM});
		my $maps = $pagestate{$page}{OSM};
		foreach my $map (keys %$maps) {
			next unless (exists $maps->{$map}{'waypoints'} and
				$maps->{$map}{'waypoints'});
			$waypoints{$map}{$page} = $maps->{$map}{'waypoints'};
		}
	}

	# Draw lines between waypoints whose pages link each other.
	foreach my $map (keys %waypoints) {
		foreach my $page (keys %{$waypoints{$map}}) {
			next unless (exists $links{$page});
			foreach my $otherpage (@{$links{$page}}) {
				my $bestlink = bestlink($page, $otherpage);
				next unless (exists $waypoints{$map}{$bestlink});
				foreach my $wp (values %{$waypoints{$map}{$page}}) {
					foreach my $otherwp (values %{$waypoints{$map}{$bestlink}}) {
						push(@{$linestrings{$map}}, [$wp, $otherwp]);
					}
				}
			}
		}
	}
	writejson(\%waypoints, \%linestrings);
	$waypoint_changed = 0;
}

sub writejson($;$) {
	my %waypoints = %{$_[0]};
	my %linestrings = %{$_[1]};

	foreach my $map (keys %waypoints) {
		my %geojson = (
			"type" => "FeatureCollection",
			"features" => [],
		);
		foreach my $page (keys %{$waypoints{$map}}) {
			foreach my $wp (values %{$waypoints{$map}{$page}}) {
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
		foreach my $linestring (@{$linestrings{$map}}) {
			my $coord = [
				[
					$linestring->[0]->{'lon'} + 0.0,
					$linestring->[0]->{'lat'} + 0.0,
				],
				[
					$linestring->[1]->{'lon'} + 0.0,
					$linestring->[1]->{'lat'} + 0.0,
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
		writefile("$map.js", "$config{destdir}/ikiwiki/" . OSM,
			"var geojson_$map = " . to_json(\%geojson));
	}
}

# pipe some data through the HTML scrubber
#
# code taken from the meta.pm plugin
sub scrub($$$) {
	if (IkiWiki::Plugin::htmlscrubber->can("sanitize")) {
		return IkiWiki::Plugin::htmlscrubber::sanitize(
			content => shift, page => shift, destpage => shift);
	}
	else {
		return shift;
	}
}

# taken from toggle.pm
sub format (@) {
	my %params = @_;
	my $page = $params{page};

	return $params{content} unless (exists $pagestate{$page}{OSM});
	return $params{content} unless (
		grep { exists $_->{'displays'} }
		values %{$pagestate{$page}{OSM}});

	my $js = map_setup_js($page);
	my ($before, $after) = split(m(</head>), $params{content}, 2);
	if (defined $after) {
		return $before . $js . $after;
	}
	return $js . $before;
}

sub map_setup_js(;$) {
	my $page = shift;

	my $cssurl = $config{osm_leafletcss_url} || "https://unpkg.com/leaflet@1.3.1/dist/leaflet.css";
	my $olurl = $config{osm_leafletjs_url} || "https://unpkg.com/leaflet@1.3.1/dist/leaflet.js";
	my $osmurl = urlto("ikiwiki/" . OSM . "/display_map.js", $page);

	my $code = qq(<link rel="stylesheet" href="$cssurl" crossorigin=""/>\n);
	$code .= qq(<script src="$olurl" type="text/javascript" crossorigin="" charset="utf-8"></script>\n);
	$code .= qq(<script src="$osmurl" type="text/javascript" charset="utf-8"></script>\n);
	return $code;
}

our %json_embedded;
sub load_geojson_js($$) {
	my $map = shift;
	my $dest = shift;

	return '' if ($json_embedded{$dest});
	$json_embedded{$dest} = 1;

	my $jsonurl = urlto("/ikiwiki/" . OSM . "/${map}.js", $dest);
	my $ret = qq(<script src="$jsonurl" type="text/javascript");
	$ret .= qq( charset="utf-8"></script>\n);
	return $ret;
}

sub display_map_js($$;@) {
	my $map = shift;
	my $divname = shift;
	my %options = @_;

	$options{'tilesrc'} = $config{osm_tile_source} || 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png';
	$options{'attribution'} = $config{osm_attribution} || '&copy; <a href="http://osm.org/copyright">OpenStreetMap</a> contributors';

	my $ret = qq(<script type="text/javascript">\n);
	$ret .= qq{display_map('mapdiv-$divname', geojson_$map, };
	$ret .= to_json(\%options);
	$ret .= qq{);\n</script>\n};
	return $ret;
}

1;
