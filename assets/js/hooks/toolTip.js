import { autoUpdate, computePosition, offset, arrow } from "@floating-ui/dom"

export default {
  mounted() {
    this.updated()
  },

  updateTooltip() {
    const arrowLen = this.arrow.offsetWidth

    let placement = this.placement

    autoUpdate(this.el, this.content, () => {
      const sideOffset = {
        top: 15,
        right: 10,
        bottom: 15,
        left: 10
      }[this.placement]

      computePosition(this.el, this.content, {
        placement,
        middleware: [offset(sideOffset), arrow({ element: this.arrow })]
      }).then(({ x, y, middlewareData, placement }) => {
        Object.assign(this.content.style, {
          left: `${x}px`,
          top: `${y}px`
        })

        const side = placement.split("-")[0]

        const staticSide = {
          top: "bottom",
          right: "left",
          bottom: "top",
          left: "right"
        }[side]

        if (middlewareData.arrow) {
          const { x, y } = middlewareData.arrow

          const border = {
            top: "0 1px 1px 0",
            right: "0 0 1px 1px",
            bottom: "1px 0 0 1px",
            left: "1px 1px 0 0"
          }[this.placement]

          Object.assign(this.arrow.style, {
            left: x != null ? `${x}px` : "",
            top: y != null ? `${y}px` : "",
            // Ensure the static side gets unset when
            // flipping to other placements' axes.
            right: "",
            bottom: "",
            [staticSide]: `${(-arrowLen - 1) / 2}px`,
            transform: "rotate(45deg)",
            "border-width": border
          })
        }
      })
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
