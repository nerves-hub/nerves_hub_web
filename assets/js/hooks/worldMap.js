import Leaflet from "leaflet/dist/leaflet.js"
import "leaflet.markercluster/dist/leaflet.markercluster.js"

export default {
  mounted() {
    let self = this
    let mapId = this.el.id
    this.markers = []

    var mapOptionsZoom = {
      attributionControl: false,
      zoomControl: true,
      scrollWheelZoom: true,
      boxZoom: false,
      doubleClickZoom: false,
      dragging: true,
      keyboard: false,
      maxZoom: 18,
      minZoom: 1.4,
      renderer: Leaflet.canvas()
    }

    var mapStyle = {
      stroke: true,
      color: "#2A2D30",
      fillColor: "#b7bec5",
      weight: 0.5,
      opacity: 1,
      fillOpacity: 0.5
    }

    // initialize the map
    this.map = Leaflet.map(mapId, mapOptionsZoom).setView([0, 0], 1)
    this.map.setMaxBounds(this.map.getBounds())
    this.handleEvent("markers", ({ markers }) => {
      self.markers = markers
      self.updated()
    })

    // load GeoJSON from an external file
    fetch("/geo/world.geojson")
      .then(res => res.json())
      .then(data => {
        Leaflet.geoJson(data, { style: mapStyle }).addTo(this.map)
        this.pushEvent("map_ready", {})
      })
  },
  updated() {
    let mode = this.el.dataset.mode

    var myRenderer = Leaflet.canvas({ padding: 0.5 })
    var clusterLayer = Leaflet.markerClusterGroup({
      chunkedLoading: true,
      chunkProgress: this.updateProgressBar
    })

    var defaultOptions = {
      radius: 6,
      weight: 1,
      opacity: 0,
      fillOpacity: 1,
      renderer: myRenderer,
      fillColor: "#4dd54f"
    }

    var offlineOptions = Object.assign(defaultOptions, {
      fillColor: "rgba(196,49,49,1)"
    })
    var outdatedOptions = Object.assign(defaultOptions, {
      fillColor: "rgba(99,99,99,1)"
    })

    var devices = this.markers.reduce(function(acc, marker) {
      let location = marker["l"]
      var latLng = [location["at"], location["ng"]]

      // if no location or we don't care about mode, move on
      if (!location["ng"] && !location["at"]) return acc
      if (!["connected", "updated"].includes(mode)) return acc

      if (mode == "connected") {
        if (marker["s"] == "connected") {
          acc.push(Leaflet.circleMarker(latLng, defaultOptions))
        } else {
          acc.push(Leaflet.circleMarker(latLng, offlineOptions))
        }
      }

      if (mode == "updated") {
        if (marker["lf"]) {
          acc.push(Leaflet.circleMarker(latLng, defaultOptions))
        } else {
          acc.push(Leaflet.circleMarker(latLng, outdatedOptions))
        }
      }
      return acc
    }, [])

    clusterLayer.addLayers(devices)
    this.map.addLayer(clusterLayer)
  }
}
