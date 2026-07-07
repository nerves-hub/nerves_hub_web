// Toggles the collapsed/expanded sidebar state. Mirrors the theme switcher:
// the state lives in `data-sidebar` on <html> and is persisted to localStorage
// (restored before first paint by the inline script in root.html.heex).
export default {
  mounted() {
    this.el.addEventListener("click", () => {
      const collapsed =
        document.documentElement.getAttribute("data-sidebar") === "collapsed"

      if (collapsed) {
        document.documentElement.removeAttribute("data-sidebar")
        localStorage.sidebar = "expanded"
      } else {
        document.documentElement.setAttribute("data-sidebar", "collapsed")
        localStorage.sidebar = "collapsed"
      }
    })
  },
}
