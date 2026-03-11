export default {
  mounted() {
    this.init()
  },
  init() {
    document.addEventListener("visibilitychange", () => {
      if (this.liveSocket.isConnected()) {
        this.pushEvent("page_visibility_change", {
          visible: document.visibilityState === "visible",
        })
      }
    })
  },
}
