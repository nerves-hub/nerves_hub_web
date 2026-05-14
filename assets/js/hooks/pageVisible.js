export default {
  mounted() {
    this.controller = new AbortController()

    document.addEventListener(
      "visibilitychange",
      () => {
        const visibility = document.visibilityState === "visible"
        try {
          if (liveSocket.isConnected()) {
            this.pushEvent("page_visibility_change", { visible: visibility })
          }
        } catch (error) {
          console.error(
            "Error during visibilitychange event callback with visibilityState=${visibility} : ",
            error,
          )
          this.controller.abort()
        }
      },
      { signal: this.controller.signal },
    )
  },
  destroyed() {
    this.controller.abort()
  },
}
