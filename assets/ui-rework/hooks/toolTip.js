import { computePosition, offset, arrow } from "@floating-ui/dom"

export default {
  mounted() {
    this.updated()
  },

  updateTooltip() {
    computePosition(this.el, this.content, {
      placement: this.placement,
      middleware: [offset(15), arrow({ element: this.arrow })]
    }).then(({ x, y, middlewareData }) => {
      Object.assign(this.content.style, {
        top: `${y}px`,
        left: `${x}px`
      })

      if (middlewareData.arrow) {
        const { x } = middlewareData.arrow

        Object.assign(this.arrow.style, {
          left: `${x}px`,
          top: `${-this.arrow.offsetHeight / 2}px`
        })
      }
    })
  },

  showTooltip() {
    this.content.style.display = "block"
    this.updateTooltip()
  },

  hideTooltip() {
    this.content.style.display = ""
  },

  updated() {
    this.content = this.el.getElementsByClassName("tooltip-content")[0]
    this.arrow = this.el.getElementsByClassName("tooltip-arrow")[0]
    this.placement = this.el.dataset.placement || "bottom"

    this.el.addEventListener("mouseover", this.showTooltip.bind(this))
    this.el.addEventListener("mouseout", this.hideTooltip.bind(this))
  }
}
