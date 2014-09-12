#!/usr/bin/perl
# Copyright 2011 Blars Blarson
# Released under GPL version 2

package IkiWiki::Plugin::osm;
use utf8;
use strict;
use warnings;
use IkiWiki 3.0;

sub import {
	add_underlay("osm");
	hook(type => "getsetup", id => "osm", call => \&getsetup);
	hook(type => "format", id => "osm", call => \&format);
	hook(type => "preprocess", id => "osm", call => \&preprocess);
	hook(type => "preprocess", id => "waypoint", call => \&process_waypoint);
	hook(type => "savestate", id => "waypoint", call => \&savestate);
	hook(type => "cgi", id => "osm", call => \&cgi);
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
			description => "the default zoom when you click on the map link",
			safe => 1,
			rebuild => 1,
		},
		osm_default_icon => {
			type => "string",
			example => "ikiwiki/images/osm.png",
			description => "the icon shown on links and on the main map",
			safe => 0,
			rebuild => 1,
		},
		osm_alt => {
			type => "string",
			example => "",
			description => "the alt tag of links, defaults to empty",
			safe => 0,
			rebuild => 1,
		},
		osm_format => {
			type => "string",
			example => "KML",
			description => "the output format for waypoints, can be KML, GeoJSON or CSV (one or many, comma-separated)",
			safe => 1,
			rebuild => 1,
		},
		osm_tag_default_icon => {
			type => "string",
			example => "icon.png",
			description => "the icon attached to a tag, displayed on the map for tagged pages",
			safe => 0,
			rebuild => 1,
		},
		osm_openlayers_url => {
			type => "string",
			example => "http://www.openlayers.org/api/OpenLayers.js",
			description => "Url for the OpenLayers.js file",
			safe => 0,
			rebuild => 1,
		},
		osm_layers => {
			type => "string",
			example => { 'OSM', 'GoogleSatellite' },
			description => "Layers to use in the map. Can be either the 'OSM' string or a type option for Google maps (GoogleNormal, GoogleSatellite, GoogleHybrid or GooglePhysical). It can also be an arbitrary URL in a syntax acceptable for OpenLayers.Layer.OSM.url parameter.",
			safe => 0,
			rebuild => 1,
		},
	        osm_google_apikey => {
			type => "string",
			example => "",
			description => "Google maps API key, Google layer not used if missing, see https://code.google.com/apis/console/ to get an API key",
			safe => 1,
			rebuild => 1,
		},
}

sub register_rendered_files {
	my $map = shift;
	my $page = shift;
	my $dest = shift;

	if ($page eq $dest) {
		my %formats = get_formats();
		if ($formats{'GeoJSON'}) {
			will_render($page, "$map/pois.json");
		}
		if ($formats{'CSV'}) {
			will_render($page, "$map/pois.txt");
		}
		if ($formats{'KML'}) {
			will_render($page, "$map/pois.kml");
		}
	}
}

sub preprocess {
	my %params=@_;
	my $page = $params{page};
	my $dest = $params{destpage};
	my $loc = $params{loc}; # sanitized below
	my $lat = $params{lat}; # sanitized below
	my $lon = $params{lon}; # sanitized below
	my $href = $params{href};

	my ($width, $height, $float);
	$height = scrub($params{'height'} || "300px", $page, $dest); # sanitized here
	$width = scrub($params{'width'} || "500px", $page, $dest); # sanitized here
	$float = (defined($params{'right'}) && 'right') || (defined($params{'left'}) && 'left'); # sanitized here
	
	my $zoom = scrub($params{'zoom'} // $config{'osm_default_zoom'} // 15, $page, $dest); # sanitized below
	my $map;
	$map = $params{'map'} || 'map';
	
	$map = scrub($map, $page, $dest); # sanitized here
	my $name = scrub($params{'name'} || $map, $page, $dest);

	if (defined($lon) || defined($lat) || defined($loc)) {
		($lon, $lat) = scrub_lonlat($loc, $lon, $lat);
	}

	if ($zoom !~ /^\d\d?$/ || $zoom < 2 || $zoom > 18) {
		error("Bad zoom");
	}

	if (! defined $href || ! length $href) {
		$href=IkiWiki::cgiurl(
			do => "osm",
			map => $map,
		);
	}

	register_rendered_files($map, $page, $dest);

	$pagestate{$page}{'osm'}{$map}{'displays'}{$name} = {
		height => $height,
		width => $width,
		float => $float,
		zoom => $zoom,
		fullscreen => 0,
		editable => defined($params{'editable'}),
		lat => $lat,
		lon => $lon,
		href => $href,
		google_apikey => $config{'osm_google_apikey'},
	};
	return "<div id=\"mapdiv-$name\"></div>";
}

sub process_waypoint {
	my %params=@_;
	my $loc = $params{'loc'}; # sanitized below
	my $lat = $params{'lat'}; # sanitized below
	my $lon = $params{'lon'}; # sanitized below
	my $page = $params{'page'}; # not sanitized?
	my $dest = $params{'destpage'}; # not sanitized?
	my $hidden = defined($params{'hidden'}); # sanitized here
	my ($p) = $page =~ /(?:^|\/)([^\/]+)\/?$/; # shorter page name
	my $name = scrub($params{'name'} || $p, $page, $dest); # sanitized here
	my $desc = scrub($params{'desc'} || '', $page, $dest); # sanitized here
	my $zoom = scrub($params{'zoom'} // $config{'osm_default_zoom'} // 15, $page, $dest); # sanitized below
	my $icon = $config{'osm_default_icon'} || "ikiwiki/images/osm.png"; # sanitized: we trust $config
	my $map = scrub($params{'map'} || 'map', $page, $dest); # sanitized here
	my $alt = $config{'osm_alt'} ? "alt=\"$config{'osm_alt'}\"" : ''; # sanitized: we trust $config
	if ($zoom !~ /^\d\d?$/ || $zoom < 2 || $zoom > 18) {
		error("Bad zoom");
	}

	($lon, $lat) = scrub_lonlat($loc, $lon, $lat);
	if (!defined($lat) || !defined($lon)) {
		error("Must specify lat and lon");
	}

	my $tag = $params{'tag'};
	foreach my $t (keys %{$typedlinks{$page}{'tag'}}) {
		if ($icon = get_tag_icon($t)) {
			$tag = $t;
			last;
		}
		$t =~ s!/$config{'tagbase'}/!!;
		if ($icon = get_tag_icon($t)) {
			$tag = $t;
			last;
		}
	}
	$icon = urlto($icon, $dest, 1);
	$icon =~ s!/*$!!; # hack - urlto shouldn't be appending a slash in the first place
	$tag = '' unless $tag;
	register_rendered_files($map, $page, $dest);
	$pagestate{$page}{'osm'}{$map}{'waypoints'}{$name} = {
		page => $page,
		desc => $desc,
		icon => $icon,
		tag => $tag,
		lat => $lat,
		lon => $lon,
		# How to link back to the page from the map, not to be
		# confused with the URL of the map itself sent to the
		# embeded map below. Note: used in generated KML etc file,
		# so must be absolute.
		href => urlto($page),
	};

	my $mapurl = IkiWiki::cgiurl(
		do => "osm",
		map => $map,
		lat => $lat,
		lon => $lon,
		zoom => $zoom,
	);
	my $output = '';
	if (defined($params{'embed'})) {
		$output .= preprocess(%params,
			href => $mapurl,
		);
	}
	if (!$hidden) {
		$output .= "<a href=\"$mapurl\"><img class=\"img\" src=\"$icon\" $alt /></a>";
	}
	return $output;
}

# get the icon from the given tag
sub get_tag_icon($) {
	my $tag = shift;
	# look for an icon attached to the tag
	my $attached = $tag . '/' . $config{'osm_tag_default_icon'};
	if (srcfile($attached)) {
		return $attached;
	}
	else {
		return undef;
	}
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
	return ($lon, $lat);
}

sub savestate {
	my %waypoints = ();
	my %linestrings = ();

	foreach my $page (keys %pagestate) {
		if (exists $pagestate{$page}{'osm'}) {
			foreach my $map (keys %{$pagestate{$page}{'osm'}}) {
				foreach my $name (keys %{$pagestate{$page}{'osm'}{$map}{'waypoints'}}) {
					debug("found waypoint $name");
					$waypoints{$map}{$name} = $pagestate{$page}{'osm'}{$map}{'waypoints'}{$name};
				}
			}
		}
	}

	foreach my $page (keys %pagestate) {
		if (exists $pagestate{$page}{'osm'}) {
			foreach my $map (keys %{$pagestate{$page}{'osm'}}) {
				# examine the links on this page
				foreach my $name (keys %{$pagestate{$page}{'osm'}{$map}{'waypoints'}}) {
					if (exists $links{$page}) {
						foreach my $otherpage (@{$links{$page}}) {
							if (exists $waypoints{$map}{$otherpage}) {
								push(@{$linestrings{$map}}, [
									[ $waypoints{$map}{$name}{'lon'}, $waypoints{$map}{$name}{'lat'} ],
									[ $waypoints{$map}{$otherpage}{'lon'}, $waypoints{$map}{$otherpage}{'lat'} ]
								]);
							}
						}
					}
				}
			}
			# clear the state, it will be regenerated on the next parse
			# the idea here is to clear up removed waypoints...
			$pagestate{$page}{'osm'} = ();
		}
	}

	my %formats = get_formats();
	if ($formats{'GeoJSON'}) {
		writejson(\%waypoints, \%linestrings);
	}
	if ($formats{'CSV'}) {
		writecsvs(\%waypoints, \%linestrings);
	}
	if ($formats{'KML'}) {
		writekml(\%waypoints, \%linestrings);
	}
}

sub writejson($;$) {
	my %waypoints = %{$_[0]};
	my %linestrings = %{$_[1]};
	eval q{use JSON};
	error $@ if $@;
	foreach my $map (keys %waypoints) {
		my %geojson = ( "type" => "FeatureCollection", "features" => []);
		foreach my $name (keys %{$waypoints{$map}}) {
			my %marker = ( "type" => "Feature",
				"geometry" => { "type" => "Point", "coordinates" => [ $waypoints{$map}{$name}{'lon'}, $waypoints{$map}{$name}{'lat'} ] },
				"properties" => $waypoints{$map}{$name} );
			push @{$geojson{'features'}}, \%marker;
		}
		foreach my $linestring (@{$linestrings{$map}}) {
			my %json  = ( "type" => "Feature",
				"geometry" => { "type" => "LineString", "coordinates" => $linestring });
			push @{$geojson{'features'}}, \%json;
		}
		writefile("pois.json", $config{destdir} . "/$map", to_json(\%geojson));
	}
}

sub writekml($;$) {
	my %waypoints = %{$_[0]};
	my %linestrings = %{$_[1]};
	eval q{use XML::Writer};
	error $@ if $@;
	foreach my $map (keys %waypoints) {
		my $output;
		my $writer = XML::Writer->new( OUTPUT => \$output,
			DATA_MODE => 1, DATA_INDENT => ' ', ENCODING => 'UTF-8');
		$writer->xmlDecl();
		$writer->startTag("kml", "xmlns" => "http://www.opengis.net/kml/2.2");
		$writer->startTag("Document");

		# first pass: get the icons
		my %tags_map = (); # keep track of tags seen
		foreach my $name (keys %{$waypoints{$map}}) {
			my %options = %{$waypoints{$map}{$name}};
			if (!$tags_map{$options{tag}}) {
			    debug("found new style " . $options{tag});
			    $tags_map{$options{tag}} = ();
			    $writer->startTag("Style", id => $options{tag});
			    $writer->startTag("IconStyle");
			    $writer->startTag("Icon");
			    $writer->startTag("href");
			    $writer->characters($options{icon});
			    $writer->endTag();
			    $writer->endTag();
			    $writer->endTag();
			    $writer->endTag();
			}
			$tags_map{$options{tag}}{$name} = \%options;
		}
	
		foreach my $name (keys %{$waypoints{$map}}) {
			my %options = %{$waypoints{$map}{$name}};
			$writer->startTag("Placemark");
			$writer->startTag("name");
			$writer->characters($name);
			$writer->endTag();
			$writer->startTag("styleUrl");
			$writer->characters('#' . $options{tag});
			$writer->endTag();
			#$writer->emptyTag('atom:link', href => $options{href});
			# to make it easier for us as the atom:link parameter is
			# hard to access from javascript
			$writer->startTag('href');
			$writer->characters($options{href});
			$writer->endTag();
			$writer->startTag("description");
			$writer->characters($options{desc});
			$writer->endTag();
			$writer->startTag("Point");
			$writer->startTag("coordinates");
			$writer->characters($options{lon} . "," . $options{lat});
			$writer->endTag();
			$writer->endTag();
			$writer->endTag();
		}
		
		my $i = 0;
		foreach my $linestring (@{$linestrings{$map}}) {
			$writer->startTag("Placemark");
			$writer->startTag("name");
			$writer->characters("linestring " . $i++);
			$writer->endTag();
			$writer->startTag("LineString");
			$writer->startTag("coordinates");
			my $str = '';
			foreach my $coord (@{$linestring}) {
				$str .= join(',', @{$coord}) . " \n";
			}
			$writer->characters($str);
			$writer->endTag();
			$writer->endTag();
			$writer->endTag();
		}
		$writer->endTag();
		$writer->endTag();
		$writer->end();

		writefile("pois.kml", $config{destdir} . "/$map", $output);
	}
}

sub writecsvs($;$) {
	my %waypoints = %{$_[0]};
	foreach my $map (keys %waypoints) {
		my $poisf = "lat\tlon\ttitle\tdescription\ticon\ticonSize\ticonOffset\n";
		foreach my $name (keys %{$waypoints{$map}}) {
			my %options = %{$waypoints{$map}{$name}};
			my $line = 
				$options{'lat'} . "\t" .
				$options{'lon'} . "\t" .
				$name . "\t" .
				$options{'desc'} . '<br /><a href="' . $options{'page'} . '">' . $name . "</a>\t" .
				$options{'icon'} . "\n";
			$poisf .= $line;
		}
		writefile("pois.txt", $config{destdir} . "/$map", $poisf);
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
	my %params=@_;

	if ($params{content}=~m!<div[^>]*id="mapdiv-[^"]*"[^>]*>!g) {
		if (! ($params{content}=~s!</body>!include_javascript($params{page})."</body>"!em)) {
			# no <body> tag, probably in preview mode
			$params{content}=$params{content} . include_javascript($params{page});
		}
	}
	return $params{content};
}

sub preferred_format() {
	if (!defined($config{'osm_format'}) || !$config{'osm_format'}) {
		$config{'osm_format'} = 'KML';
	}
	my @spl = split(/, */, $config{'osm_format'});
	return shift @spl;
}

sub get_formats() {
	if (!defined($config{'osm_format'}) || !$config{'osm_format'}) {
		$config{'osm_format'} = 'KML';
	}
	map { $_ => 1 } split(/, */, $config{'osm_format'});
}

sub include_javascript ($) {
	my $page=shift;
	my $loader;

	if (exists $pagestate{$page}{'osm'}) {
		foreach my $map (keys %{$pagestate{$page}{'osm'}}) {
			foreach my $name (keys %{$pagestate{$page}{'osm'}{$map}{'displays'}}) {
				$loader .= map_setup_code($map, $name, %{$pagestate{$page}{'osm'}{$map}{'displays'}{$name}});
			}
		}
	}
	if ($loader) {
		return embed_map_code($page) . "<script type=\"text/javascript\">$loader</script>";
	}
	else {
        	return '';
	}
}

sub cgi($) {
	my $cgi=shift;

	return unless defined $cgi->param('do') &&
		$cgi->param("do") eq "osm";
	
	IkiWiki::loadindex();

	IkiWiki::decode_cgi_utf8($cgi);

	my $map = $cgi->param('map');
	if (!defined $map || $map !~ /^[a-z]*$/) {
		error("invalid map parameter");
	}

	print "Content-Type: text/html\r\n";
	print ("\r\n");
	print "<html><body>";
	print "<div id=\"mapdiv-$map\"></div>";
	print embed_map_code();
	print "<script type=\"text/javascript\">";
	print map_setup_code($map, $map,
		lat => "urlParams['lat']",
		lon => "urlParams['lon']",
		zoom => "urlParams['zoom']",
		fullscreen => 1,
		editable => 1,
		google_apikey => $config{'osm_google_apikey'},
	);
	print "</script>";
	print "</body></html>";

	exit 0;
}

sub embed_map_code(;$) {
	my $page=shift;
	my $olurl = $config{osm_openlayers_url} || "http://www.openlayers.org/api/OpenLayers.js";
	my $code = '<script src="'.$olurl.'" type="text/javascript" charset="utf-8"></script>'."\n".
		'<script src="'.urlto("ikiwiki/osm.js", $page).
		'" type="text/javascript" charset="utf-8"></script>'."\n";
	if ($config{'osm_google_apikey'}) {
	    $code .= '<script src="http://maps.google.com/maps?file=api&amp;v=2&amp;key='.$config{'osm_google_apikey'}.'&sensor=false" type="text/javascript" charset="utf-8"></script>';
	}
	return $code;
}

sub map_setup_code($;@) {
	my $map=shift;
	my $name=shift;
	my %options=@_;

	my $mapurl = $config{osm_map_url};

	eval q{use JSON};
	error $@ if $@;
				
	$options{'format'} = preferred_format();

	my %formats = get_formats();
	if ($formats{'GeoJSON'}) {
		$options{'jsonurl'} = urlto($map."/pois.json");
	}
	if ($formats{'CSV'}) {
		$options{'csvurl'} = urlto($map."/pois.txt");
	}
	if ($formats{'KML'}) {
		$options{'kmlurl'} = urlto($map."/pois.kml");
	}

	if ($mapurl) {
		$options{'mapurl'} = $mapurl;
	}
        $options{'layers'} = $config{osm_layers};

	$name=~s/'//g; # $name comes from user input
	return "mapsetup('mapdiv-$name', " . to_json(\%options) . ");";
}

1;
