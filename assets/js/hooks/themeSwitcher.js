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

      document
        .getElementById("theme-" + theme)
        .setAttribute("data-selected", "true")

      if (theme === "system") {
        setupSystemTheme()
      } else {
        document.documentElement.setAttribute("data-theme", theme)
      }
    })
  },
}
