export default {
  mounted() {
    document.addEventListener("visibilitychange", () => {
      try {
        if (liveSocket.isConnected()) {
          this.pushEvent("page_visibility_change", {
            visible: document.visibilityState === "visible",
          })
        }
      } catch (error) {
        console.error("Error during visibilitychange event callback:", error)
      }
    })
  },
}
