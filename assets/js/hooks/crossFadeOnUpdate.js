export default {
  updated() {
    this.el.animate([{ opacity: 0 }, { opacity: 1 }], {
      duration: 700,
      easing: "ease-in",
    })
  },
}
