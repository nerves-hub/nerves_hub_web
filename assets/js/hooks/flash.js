//
// Hides the flash after 8 seconds, but resets the timer if you hover over it
//
// taken from https://github.com/fly-apps/live_beats/blob/master/assets/js/app.js#L29-L40
export default {
  mounted() {
    let hide = () =>
      liveSocket.execJS(this.el, this.el.getAttribute("phx-click"))
    this.timer = setTimeout(() => hide(), 8000)
    this.el.addEventListener("phx:hide-start", () => clearTimeout(this.timer))
    this.el.addEventListener("mouseover", () => {
      clearTimeout(this.timer)
      this.timer = setTimeout(() => hide(), 8000)
    })
  },
  destroyed() {
    clearTimeout(this.timer)
  }
}
