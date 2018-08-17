// Copyright 2018 Martín Ferrari
function display_map(divname, geojson, options) {
	div = document.getElementById(divname);

	div.style.height = options.height;
	div.style.width = options.width;
	div.style.float = options.float;

	var map = L.map(div);
	L.tileLayer(options.tilesrc, {
		attribution: options.attribution,
	}).addTo(map);

	var bounds = L.latLngBounds();
	L.geoJSON(geojson, {
		filter: function(feature, layer) {
			return feature.type != 'LineString' || options.autolines;
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
					bounds.extend(L.latLng(lat, lon));
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
	if (!options.lat || !options.lon) {
		map.fitBounds(bounds, {
			padding: [20, 20],
		});
	} else {
		map.setView([options.lat, options.lon], options.zoom);
	}
}
