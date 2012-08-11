// taken from http://stackoverflow.com/questions/901115/get-query-string-values-in-javascript
var urlParams = {};
(function () {
	var e,
	a = /\\+/g,  // Regex for replacing addition symbol with a space
	r = /([^&=]+)=?([^&]*)/g,
	d = function (s) { return decodeURIComponent(s.replace(a, " ")); },
	q = window.location.search.substring(1);

	while (e = r.exec(q))
	urlParams[d(e[1])] = d(e[2]);
})();

function mapsetup(divname, options) {
	div = document.getElementById(divname);
	if (options.fullscreen) {
		permalink = 'permalink';
		div.style.top = 0;
		div.style.left = 0;
		div.style.position = 'absolute';
		div.style.width = '100%';
		div.style.height = '100%';
	}
	else {
		div.style.height = options.height;
		div.style.width = options.width;
		div.style.float = options.float;
		permalink = {base: options.href, title: "View larger map"};
	}
	map = new OpenLayers.Map(divname, {
		controls: [
			new OpenLayers.Control.Navigation(),
			new OpenLayers.Control.ScaleLine(),
			new OpenLayers.Control.Permalink(permalink)
		],
		displayProjection: new OpenLayers.Projection("EPSG:4326"),
		maxExtent: new OpenLayers.Bounds(-20037508.34,-20037508.34,20037508.34,20037508.34),
		projection: "EPSG:900913",
		units: "m",
		maxResolution: 156543.0339,
		numZoomLevels: 19
	});

	if (options.mapurl) {
		var newLayer = new OpenLayers.Layer.OSM("Local Tiles", options.mapurl);
		map.addLayer(newLayer);
	} else {
		map.addLayer(new OpenLayers.Layer.OSM());
	}

	// this nightmare is possible through http://docs.openlayers.org/library/spherical_mercator.html
	if (options.google_apikey && options.google_apikey != 'null') {
		googleLayer = new OpenLayers.Layer.Google(
			"Google Hybrid",
			{type: G_HYBRID_MAP,
			 'sphericalMercator': true,
			 'maxExtent': new OpenLayers.Bounds(-20037508.34,-20037508.34,20037508.34,20037508.34),
			 projection: new OpenLayers.Projection("EPSG:3857")}
		);
		map.addLayer(googleLayer);
	}
	if (options.format == 'CSV') {
		pois = new OpenLayers.Layer.Text( "CSV",
			{ location: options.csvurl,
			  projection: new OpenLayers.Projection("EPSG:4326")
			});
	} else if (options.format == 'GeoJSON') {
		pois = new OpenLayers.Layer.Vector("GeoJSON", {
			protocol: new OpenLayers.Protocol.HTTP({
				url: options.jsonurl,
				format: new OpenLayers.Format.GeoJSON()
			}),
			strategies: [new OpenLayers.Strategy.Fixed()],
			projection: new OpenLayers.Projection("EPSG:4326")
		});
	} else {
		pois = new OpenLayers.Layer.Vector("KML", {
			protocol: new OpenLayers.Protocol.HTTP({
				url: options.kmlurl,
				format: new OpenLayers.Format.KML({
					extractStyles: true,
					extractAttributes: true
				})
			}),
			strategies: [new OpenLayers.Strategy.Fixed()],
			projection: new OpenLayers.Projection("EPSG:4326")
                });
	}
	map.addLayer(pois);
	select = new OpenLayers.Control.SelectFeature(pois);
	map.addControl(select);
	select.activate();

	pois.events.on({
		"featureselected": function (event) {
			var feature = event.feature;
			var content = '<h2><a href="' + feature.attributes.href + '">' +feature.attributes.name + "</a></h2>" + feature.attributes.description;
			popup = new OpenLayers.Popup.FramedCloud("chicken",
				feature.geometry.getBounds().getCenterLonLat(),
				new OpenLayers.Size(100,100),
				content,
				null, true, function () {select.unselectAll()});
			feature.popup = popup;
			map.addPopup(popup);
		},
		"featureunselected": function (event) {
			var feature = event.feature;
			if (feature.popup) {
				map.removePopup(feature.popup);
				feature.popup.destroy();
				delete feature.popup;
			}
		}
	});

	if (options.editable) {
		vlayer = new OpenLayers.Layer.Vector( "Editable" );
		map.addControl(new OpenLayers.Control.EditingToolbar(vlayer));
		map.addLayer(vlayer);
	}

	if (options.fullscreen) {
		map.addControl(new OpenLayers.Control.PanZoomBar());
		map.addControl(new OpenLayers.Control.LayerSwitcher({'ascending':false}));
		map.addControl(new OpenLayers.Control.MousePosition());
		map.addControl(new OpenLayers.Control.KeyboardDefaults());
	} else {
		map.addControl(new OpenLayers.Control.ZoomPanel());
	}

	//Set start centrepoint and zoom    
	if (!options.lat || !options.lon) {
		options.lat = urlParams['lat'];
		options.lon = urlParams['lon'];
	}
	if (!options.zoom) {
		options.zoom = urlParams['zoom'];
	}
	if (options.lat && options.lon) {
		var lat = options.lat;
		var lon = options.lon;
		var zoom= options.zoom || 10;
		center = new OpenLayers.LonLat( lon, lat ).transform(
			new OpenLayers.Projection("EPSG:4326"), // transform from WGS 1984
			map.getProjectionObject() // to Spherical Mercator Projection
		);
		map.setCenter (center, zoom);
	} else {
		pois.events.register("loadend", this, function () { map.zoomToExtent(pois.getDataExtent()); });
	}
}
