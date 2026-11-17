export default {
  mounted() {
    if (
      this.el.getAttribute("data-theme-option") === localStorage.theme ||
      (this.el.getAttribute("data-theme-option") === "dark" &&
        localStorage.theme === null)
    ) {
      this.el.setAttribute("data-selected", "true")
    }

    this.el.addEventListener("click", (e) => {
      removeThemeEventListener()

      let theme = this.el.getAttribute("data-theme-option")

      localStorage.theme = theme

      const itemsArray = Array.from(
        document.getElementsByClassName("theme-selectors"),
      )
      itemsArray.forEach((item) => item.setAttribute("data-selected", "false"))

      // The user menu can be on the page twice (the sidebar's, and the
      // phone top bar's), so mark every button for this theme.
      document
        .querySelectorAll(`.theme-selectors[data-theme-option="${theme}"]`)
        .forEach((item) => item.setAttribute("data-selected", "true"))

      if (theme === "system") {
        setupSystemTheme()
      } else {
        document.documentElement.setAttribute("data-theme", theme)
        window.dispatchEvent(new Event("themeUpdated"))
      }
    })
  },
}
