export default {
  mounted() {
    this.init()
  },
  init() {
    document.addEventListener("visibilitychange", () => {
      this.pushEvent("page_visibility_change", {
        visible: document.visibilityState === "visible"
      })
    })
  }
}
