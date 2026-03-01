import mapboxgl from "mapbox-gl"

export default {
  mounted() {
    let accessToken = this.el.dataset.accessToken
    let style = this.el.dataset.style
    let centerLng = this.el.dataset.centerLng
    let centerLat = this.el.dataset.centerLat
    let zoom = this.el.dataset.zoom
    let source = this.el.dataset.source

    const ctx = this.el

    mapboxgl.accessToken = accessToken

    this.map = new mapboxgl.Map({
      container: ctx,
      style: style,
      center: [centerLng, centerLat],
      zoom: zoom
    })

    this.map.addControl(new mapboxgl.NavigationControl({ showCompass: false }))

    source = (source || "").toLowerCase()

    if (source == "gps" || source == "manual") {
      new mapboxgl.Marker({ color: "rgb(99 102 241)" })
        .setLngLat([centerLng, centerLat])
        .addTo(this.map)
    }
  },

  destroyed() {
    this.map.remove()
  }
}
