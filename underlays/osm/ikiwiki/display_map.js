// Copyright 2018 Martín Ferrari
function display_map(divname, geojson, options) {
	div = document.getElementById(divname);

	if (options.fullscreen) {
		permalink = 'permalink';
		div.style.top = 0;
		div.style.left = 0;
		div.style.position = 'absolute';
		div.style.width = '100%';
		div.style.height = '100%';
	} else {
		div.style.height = options.height;
		div.style.width = options.width;
		div.style.float = options.float;
		permalink = {base: options.href, title: "View larger map"};
	}

	var map = L.map(divname);
	L.tileLayer(options.tilesrc, {
		//maxZoom: 18,
		attribution: options.attribution,
	}).addTo(map);

	var min_lat = 90, min_lon = 180, max_lat = -90, max_lon = -180;
	L.geoJSON(geojson, {
		filter: function(feature, layer) {
			return feature.type != 'LineString' || options.showlines;
		},
		pointToLayer: function(point, latlng) {
			if (point.properties &&
				point.properties.id == options.highlight) {
				return L.marker(latlng);
			}
			return L.circleMarker(latlng, {
				radius: 8,
				color: "#000",
				weight: 1,
				opacity: 1,
				fillColor: "#ff7800",
				fillOpacity: 0.8
			});
		},
		onEachFeature: function(feature, layer) {
			if (feature.geometry.type == 'Point') {
				var lon = feature.geometry.coordinates[0];
				var lat = feature.geometry.coordinates[1];
				if (lat && lon) {
					if (lat < min_lat)
						min_lat = lat;
					if (lon < min_lon)
						min_lon = lon;
					if (lat > max_lat)
						max_lat = lat;
					if (lon > max_lon)
						max_lon = lon;
				}
			} else {
				layer.options.interactive = false;
                        }
			if (!feature.properties) {
				return;
			}
			var content = '<h2>';
			if (! options.nolinkpages) {
				content += '<a href="' +
					feature.properties.href + '">' +
					feature.properties.name + '</a>';
			} else {
				content += feature.properties.name;
			}
			content += "</h2>";
			if (feature.properties.desc) {
				content += feature.properties.desc;
			}
			layer.bindPopup(content);
		}
	}).addTo(map);
	if (!options.lat || options.lon) {
		options.lat = (max_lat + min_lat) / 2.0;
		options.lon = (max_lon + min_lon) / 2.0;
	}
	map.setView([options.lat, options.lon], options.zoom || 13);
}
