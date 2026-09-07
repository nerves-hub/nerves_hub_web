// Sizes the deployment workflow diagram to its panel.
//
// LiveFlow decides how big the diagram is drawn by fitting it to the room it has
// been given, and its own fit hardcodes a padding of 0.1 — so the diagram fills
// 80% of the panel however much space there is, with no option for it. Its fit
// also animates the viewport over 200ms rather than setting it, so a second fit
// afterwards reads as the diagram being sized twice.
//
// So LiveFlow does no fitting (`fit_view_on_init` is off) and this does it once,
// working out the same geometry and setting the viewport through the
// `lf:set_viewport` event its hook listens for on the window. One fit, no
// animation, and a padding of our choosing.

// How much of the panel to leave clear around the diagram, per side.
const PADDING = 0.04

const RESIZE_DEBOUNCE = 150

function fit(container) {
  const viewport = container.querySelector(".lf-viewport")
  const nodes = container.querySelectorAll(".lf-node[data-node-id]")

  if (!viewport || nodes.length === 0) return false

  let minX = Infinity,
    minY = Infinity,
    maxX = -Infinity,
    maxY = -Infinity

  nodes.forEach(node => {
    const x = parseFloat(node.style.left) || 0
    const y = parseFloat(node.style.top) || 0

    minX = Math.min(minX, x)
    minY = Math.min(minY, y)
    maxX = Math.max(maxX, x + node.offsetWidth)
    maxY = Math.max(maxY, y + node.offsetHeight)
  })

  const graphWidth = maxX - minX
  const graphHeight = maxY - minY
  const rect = container.getBoundingClientRect()

  // Nothing has been laid out yet; try again on the next frame.
  if (!(graphWidth > 0 && graphHeight > 0 && rect.width > 0 && rect.height > 0)) {
    return false
  }

  const zoom = Math.min(
    (rect.width * (1 - PADDING * 2)) / graphWidth,
    (rect.height * (1 - PADDING * 2)) / graphHeight,
    parseFloat(container.dataset.maxZoom) || 4
  )

  window.dispatchEvent(
    new CustomEvent("phx:lf:set_viewport", {
      detail: {
        x: rect.width / 2 - (minX + graphWidth / 2) * zoom,
        y: rect.height / 2 - (minY + graphHeight / 2) * zoom,
        zoom: zoom
      }
    })
  )

  return true
}

export default {
  mounted() {
    // Runs before LiveFlow's own hook, which is on a descendant, so wait for it
    // to have registered its listener and for the nodes to have been laid out.
    this.fitWhenReady = attempts => {
      if (attempts > 0 && !this.refit()) {
        window.requestAnimationFrame(() => this.fitWhenReady(attempts - 1))
      }
    }

    this.refit = () => {
      const container = this.el.querySelector(".lf-container")

      return container ? fit(container) : false
    }

    window.requestAnimationFrame(() => this.fitWhenReady(10))

    this.onResize = () => {
      window.clearTimeout(this.resizeTimer)
      this.resizeTimer = window.setTimeout(this.refit, RESIZE_DEBOUNCE)
    }

    window.addEventListener("resize", this.onResize)
  },

  destroyed() {
    window.clearTimeout(this.resizeTimer)
    window.removeEventListener("resize", this.onResize)
  }
}
