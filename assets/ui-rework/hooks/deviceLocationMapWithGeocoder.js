import mapboxgl from "mapbox-gl"
import MapboxGeocoder from "@mapbox/mapbox-gl-geocoder"

export default {
  mounted() {
    // we only ever want one marker, store reference for later use
    this.marker = undefined
    const target = this.el.dataset.target
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

    geolocate.on("geolocate", e => {
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
        this.pushEventTo(target, "update-device-location", {
          lng: lngLat.lng,
          lat: lngLat.lat
        })
      })

      this.map.flyTo({
        center: [e.coords.longitude, e.coords.latitude],
        zoom: 13
      })

      this.pushEventTo(target, "update-device-location", {
        lng: e.coords.longitude,
        lat: e.coords.latitude
      })
    })

    geocoder.on("result", e => {
      if (this.marker) {
        this.marker.remove()
      }

      this.marker = new mapboxgl.Marker({
        draggable: true,
        color: "rgb(99 102 241)"
      })
        .setLngLat(e.result["center"])
        .addTo(this.map)

      this.marker.on("dragend", () => {
        const lngLat = this.marker.getLngLat()
        this.pushEventTo(target, "update-device-location", {
          lng: lngLat.lng,
          lat: lngLat.lat
        })
      })

      this.map.flyTo({
        center: e.result["center"],
        zoom: 13
      })

      this.pushEventTo(target, "update-device-location", {
        lng: e.result["center"][0],
        lat: e.result["center"][1]
      })
    })
  },

  destroyed() {
    this.map.remove()
  }
}
