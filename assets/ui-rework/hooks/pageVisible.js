export default {
  mounted() {
    this.init()
  },
  init() {
    document.addEventListener("visibilitychange", () => {
      console.log("visibility changed", document.visibilityState)
      this.pushEvent("page_visibility_change", {
        visible: document.visibilityState === "visible"
      })
    })
  }
}
