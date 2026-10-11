import mapboxgl from "mapbox-gl"
import { mapboxStyleUrl, trackMapStyle } from "../helpers/mapStyle.js"

export default {
  mounted() {
    let accessToken = this.el.dataset.accessToken
    let centerLng = this.el.dataset.centerLng
    let centerLat = this.el.dataset.centerLat
    let zoom = this.el.dataset.zoom
    let source = this.el.dataset.source

    const ctx = this.el

    mapboxgl.accessToken = accessToken

    this.map = new mapboxgl.Map({
      container: ctx,
      style: mapboxStyleUrl(this.el.dataset.mapStyle),
      center: [centerLng, centerLat],
      zoom: zoom,
    })

    this.map.addControl(new mapboxgl.NavigationControl({ showCompass: false }))

    source = (source || "").toLowerCase()

    if (source == "gps" || source == "manual") {
      new mapboxgl.Marker({ color: "rgb(99 102 241)" })
        .setLngLat([centerLng, centerLat])
        .addTo(this.map)
    }

    this.mapStyle = trackMapStyle(this.el, this.map)
  },

  // The page re-renders `data-map-style` when the user picks a map style.
  updated() {
    this.mapStyle.apply()
  },

  destroyed() {
    this.mapStyle.stop()
    this.map.remove()
  },
}
