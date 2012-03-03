#!/usr/bin/perl
# Copyright 2011 Blars Blarson
# Released under GPL version 2

package IkiWiki::Plugin::osm;
use utf8;
use strict;
use warnings;
use IkiWiki 3.0;

sub import {
	add_underlay("javascript");
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
			example => "/ikiwiki/images/osm.png",
			description => "the icon shon on links and on the main map",
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
			description => "the icon attached to a tag so that pages tagged with that tag will have that icon on the map",
			safe => 0,
			rebuild => 1,
		},
		osm_tag_icons => {
			type => "string",
			example => {
				'test' => '/img/test.png',
				'trailer' => '/img/trailer.png'
			},
			description => "tag to icon mapping, leading slash is important!",
			safe => 0,
			rebuild => 1,
		},
}

sub preprocess {
	my %params=@_;
	my $page = $params{'page'};
	my $dest = $params{'destpage'};
	my $loc = $params{'loc'}; # sanitized below
	my $lat = $params{'lat'}; # sanitized below
	my $lon = $params{'lon'}; # sanitized below
	my $href = $params{'href'};

	my $fullscreen = defined($params{'fullscreen'}); # sanitized here
	my ($width, $height, $float);
	if ($fullscreen) {
		$height = '100%';
		$width = '100%';
		$float = 0;
	}
	else {
		$height = scrub($params{'height'} || "300px", $page, $dest); # sanitized here
		$width = scrub($params{'width'} || "500px", $page, $dest); # sanitized here
		$float = (defined($params{'right'}) && 'right') || (defined($params{'left'}) && 'left'); # sanitized here
	}
	my $zoom = scrub($params{'zoom'} // $config{'osm_default_zoom'} // 15, $page, $dest); # sanitized below
	my $map;
	if ($fullscreen) {
		$map = $params{'map'} || $page;
	}
	else {
		$map = $params{'map'} || 'map';
	}
	$map = scrub($map, $page, $dest); # sanitized here
	my $name = scrub($params{'name'} || $map, $page, $dest);

	if (defined($lon) || defined($lat) || defined($loc)) {
		($lon, $lat) = scrub_lonlat($loc, $lon, $lat);
	}

	if ($zoom !~ /^\d\d?$/ || $zoom < 2 || $zoom > 18) {
		error("Bad zoom");
	}
	$pagestate{$page}{'osm'}{$map}{'displays'}{$name} = {
		height => $height,
		width => $width,
		float => $float,
		zoom => $zoom,
		fullscreen => $fullscreen,
		editable => defined($params{'editable'}),
		lat => $lat,
		lon => $lon,
		href => $href,
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
	my $icon = $config{'osm__default_icon'} || "/ikiwiki/images/osm.png"; # sanitized: we trust $config
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
	if ($tag) {
		if (!defined($config{'osm_tag_icons'}->{$tag})) {
			error("invalid tag specified, see osm_tag_icons configuration or don't specify any");
		}
		$icon = $config{'osm_tag_icons'}->{$tag};
	}
	else {
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
	}
	$icon = "/ikiwiki/images/osm.png" unless $icon;
	$tag = '' unless $tag;
	if ($page eq $dest) {
		if (!defined($config{'osm_format'}) || !$config{'osm_format'}) {
			$config{'osm_format'} = 'KML';
		}
		my %formats = map { $_ => 1 } split(/, */, $config{'osm_format'});
		if ($formats{'GeoJSON'}) {
			will_render($page,$config{destdir} . "/$map/pois.json");
		}
		if ($formats{'CSV'}) {
			will_render($page,$config{destdir} . "/$map/pois.txt");
		}
		if ($formats{'KML'}) {
			will_render($page,$config{destdir} . "/$map/pois.kml");
		}
	}
	my $href = "/ikiwiki.cgi?do=osm&map=$map&lat=$lat&lon=$lon&zoom=$zoom";
	if (defined($destsources{htmlpage($map)})) {
		$href = urlto($map,$page) . "?lat=$lat&lon=$lon&zoom=$zoom";
	}
	$pagestate{$page}{'osm'}{$map}{'waypoints'}{$name} = {
		page => $page,
		desc => $desc,
		icon => $icon,
		tag => $tag,
		lat => $lat,
		lon => $lon,
		# how to link back to the page from the map, not to be
		# confused with the URL of the map itself sent to the
		# embeded map below
		href => urlto($page,$map),
	};
	my $output = '';
	if (defined($params{'embed'})) {
		$params{'href'} = $href; # propagate down to embeded
		$output .= preprocess(%params);
	}
	if (!$hidden) {
		$href =~ s!&!&amp;!g;
		$output .= "<a href=\"$href\"><img class=\"img\" src=\"$icon\" $alt /></a>";
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
	# look for the old way: mappings
	if ($config{'osm_tag_icons'}->{$tag}) {
		return $config{'osm_tag_icons'}->{$tag};
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

	if (!defined($config{'osm_format'}) || !$config{'osm_format'}) {
		$config{'osm_format'} = 'KML';
	}
	my %formats = map { $_ => 1 } split(/, */, $config{'osm_format'});
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
		debug('writing pois file pois.json in ' . $config{destdir} . "/$map");
		writefile("pois.json",$config{destdir} . "/$map",to_json(\%geojson));
	}
}

sub writekml($;$) {
	my %waypoints = %{$_[0]};
	my %linestrings = %{$_[1]};
	eval q{use XML::Writer};
	error $@ if $@;
	foreach my $map (keys %waypoints) {
		debug("writing pois file pois.kml in " . $config{destdir} . "/$map");

=pod
Sample placemark:

<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Placemark>
    <name>Simple placemark</name>
    <description>Attached to the ground. Intelligently places itself 
       at the height of the underlying terrain.</description>
    <Point>
      <coordinates>-122.0822035425683,37.42228990140251,0</coordinates>
    </Point>
  </Placemark>
</kml>

Sample style:


        <Style id="sh_sunny_copy69">
                <IconStyle>
                        <scale>1.4</scale>
                        <Icon>
                                <href>http://waypoints.google.com/mapfiles/kml/shapes/sunny.png</href>
                        </Icon>
                        <hotSpot x="0.5" y="0.5" xunits="fraction" yunits="fraction"/>
                </IconStyle>
                <LabelStyle>
                        <color>ff00aaff</color>
                </LabelStyle>
        </Style>


=cut

		use IO::File;
		my $output = IO::File->new(">".$config{destdir} . "/$map/pois.kml");

		my $writer = XML::Writer->new( OUTPUT => $output, DATA_MODE => 1, ENCODING => 'UTF-8');
		$writer->xmlDecl();
		$writer->startTag("kml", "xmlns" => "http://www.opengis.net/kml/2.2");

		# first pass: get the icons
		foreach my $name (keys %{$waypoints{$map}}) {
			my %options = %{$waypoints{$map}{$name}};
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
		$writer->end();
		$output->close();
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
		debug("writing pois file pois.txt in " . $config{destdir} . "/$map");
		writefile("pois.txt",$config{destdir} . "/$map",$poisf);
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

sub prefered_format() {
	if (!defined($config{'osm_format'}) || !$config{'osm_format'}) {
		$config{'osm_format'} = 'KML';
	}
	my @spl = split(/, */, $config{'osm_format'});
	return shift @spl;
}

sub include_javascript ($) {
	my $page=shift;
	my $loader;

	eval q{use JSON};
	error $@ if $@;
	if (exists $pagestate{$page}{'osm'}) {
		foreach my $map (keys %{$pagestate{$page}{'osm'}}) {
			foreach my $name (keys %{$pagestate{$page}{'osm'}{$map}{'displays'}}) {
				my %options = %{$pagestate{$page}{'osm'}{$map}{'displays'}{$name}};
				$options{'map'} = $map;
				$options{'format'} = prefered_format();
				$loader .= "mapsetup(\"mapdiv-$name\", " . to_json(\%options) . ");\n";
			}
		}
	}
	if ($loader) {
		return embed_map_code() . "<script type=\"text/javascript\" charset=\"utf-8\">$loader</script>";
	}
	else {
        	return '';
	}
}

sub cgi($) {
	my $cgi=shift;

	return unless defined $cgi->param('do') &&
		$cgi->param("do") eq "osm";

	IkiWiki::decode_cgi_utf8($cgi);

	my $map = $cgi->param('map');
	if (!defined $map || $map !~ /^[a-z]*$/) {
		error("invalid map parameter");
	}

	print "Content-Type: text/html\r\n";
	print ("\r\n");
	print "<html><body>";
	print "<div id=\"mapdiv-$map\"></div>";
	print embed_map_code($map);
	print "<script type=\"text/javascript\" charset=\"utf-8\">mapsetup( 'mapdiv-$map', { 'map': '$map', 'lat': urlParams['lat'], 'lon': urlParams['lon'], 'zoom': urlParams['zoom'], 'fullscreen': 1, 'editable': 1, 'format': '" . prefered_format() . "'});</script>";
	print "</body></html>";

	exit 0;
}

sub embed_map_code() {
	return '<script src="http://www.openlayers.org/api/OpenLayers.js" type="text/javascript" charset="utf-8"></script>'.
		'<script src="'.urlto("ikiwiki/osm.js", $from).
		'" type="text/javascript" charset="utf-8"></script>'."\n";
}

1;
