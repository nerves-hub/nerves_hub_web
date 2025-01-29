import mapboxgl from "mapbox-gl"
import MapboxGeocoder from "@mapbox/mapbox-gl-geocoder"

export default {
  mounted() {
    // we only ever want one marker, store reference for later use
    this.marker = undefined
    mapboxgl.accessToken = this.el.dataset.accessToken

    this.map = new mapboxgl.Map({
      container: this.el,
      style: this.el.dataset.style,
      center: [-97.35967815000978, 39.45158853193135],
      zoom: 1
    })

    geocoder = new MapboxGeocoder({
      accessToken: mapboxgl.accessToken,
      mapboxgl: mapboxgl,
      marker: false,
      flyTo: false
    })

    geolocate = new mapboxgl.GeolocateControl({
      positionOptions: {
        enableHighAccuracy: true
      },
      trackUserLocation: false,
      showUserHeading: false,
      showUserLocation: false
    })

    // Add the control to the map.
    this.map.addControl(geocoder)
    this.map.addControl(geolocate)
    this.map.addControl(new mapboxgl.NavigationControl({ showCompass: false }))

    geolocate.on("geolocate", this.updateMarkerAndMoveMap())
    geocoder.on("result", this.updateMarkerAndMoveMap())
  },

  updateMarkerAndMoveMap() {
    return e => {
      if (this.marker) {
        this.marker.remove()
      }

      this.marker = new mapboxgl.Marker({
        draggable: true,
        color: "rgb(99 102 241)"
      })
        .setLngLat([e.coords.longitude, e.coords.latitude])
        .addTo(this.map)

      this.marker.on("dragend", () => {
        const lngLat = this.marker.getLngLat()
        this.pushEventTo(this.el.dataset.target, "update-device-location", {
          lng: lngLat.lng,
          lat: lngLat.lat
        })
      })

      this.map.flyTo({
        center: [e.coords.longitude, e.coords.latitude],
        zoom: 13
      })

      this.pushEventTo(this.el.dataset.target, "update-device-location", {
        lng: e.coords.longitude,
        lat: e.coords.latitude
      })
    }
  },

  destroyed() {
    this.map.remove()
  }
}
