// The CMD-K command palette.
//
// A global keyboard shortcut (Cmd/Ctrl+K) opens an overlay with a search box.
// Typing round-trips to the server (via the form's `phx-change`) which renders
// grouped results as `[data-palette-item]` links. This hook owns the client
// side: opening/closing the overlay, moving the highlight with the arrow keys,
// and activating the highlighted result with Enter.
//
// The pure keyboard-decision helpers are exported for unit testing (see
// commandPalette.test.js); the default export is the LiveView hook.

// Utility classes toggled on the highlighted result. Kept here (not in a
// data-attribute variant) so they don't depend on a bespoke Tailwind variant.
const ACTIVE_CLASSES = ["bg-primary/20", "text-base-50"]

// True when the event is the global open/close shortcut (Cmd+K / Ctrl+K).
export function isToggleShortcut(event) {
  return (event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k"
}

// Decide what an in-palette keypress should do, given the current highlight and
// number of results. Returns one of:
//   { type: "move", index }   - move the highlight to `index`
//   { type: "select", index } - activate the result at `index`
//   { type: "none" }          - key not handled here
export function navAction(key, { activeIndex, count }) {
  if (count === 0) return { type: "none" }

  switch (key) {
    case "ArrowDown":
      return { type: "move", index: activeIndex + 1 >= count ? 0 : activeIndex + 1 }
    case "ArrowUp":
      return { type: "move", index: activeIndex <= 0 ? count - 1 : activeIndex - 1 }
    case "Enter":
      return { type: "select", index: activeIndex >= 0 ? activeIndex : 0 }
    default:
      return { type: "none" }
  }
}

export default {
  mounted() {
    this.overlay = this.el.querySelector("[data-palette-overlay]")
    this.input = this.el.querySelector("[data-palette-input]")
    this.resultsEl = this.el.querySelector("[data-palette-results]")
    this.backdrop = this.el.querySelector("[data-palette-backdrop]")
    this.activeIndex = -1
    this.wasOpen = this.isOpen()

    this.onWindowKeydown = (event) => this.handleWindowKeydown(event)
    this.onInputKeydown = (event) => this.handleInputKeydown(event)
    this.onBackdropClick = () => this.close()
    this.onResultsClick = (event) => {
      if (event.target.closest("[data-palette-item]")) this.close()
    }

    window.addEventListener("keydown", this.onWindowKeydown)
    this.input.addEventListener("keydown", this.onInputKeydown)
    this.backdrop.addEventListener("click", this.onBackdropClick)
    this.resultsEl.addEventListener("click", this.onResultsClick)
  },

  updated() {
    // The overlay's visibility is server-owned, so react to the state the
    // server just rendered rather than toggling classes ourselves (which a
    // re-render would immediately clobber).
    const open = this.isOpen()

    if (open && !this.wasOpen) {
      // Just opened: start from a clean, focused input.
      this.input.value = ""
      this.input.focus()
      document.body.classList.add("overflow-hidden")
    } else if (!open && this.wasOpen) {
      document.body.classList.remove("overflow-hidden")
    }

    this.wasOpen = open

    // Results may have changed; reset the highlight so Enter picks the first
    // match and nothing points at a stale row.
    this.activeIndex = -1
    this.highlight()
  },

  destroyed() {
    window.removeEventListener("keydown", this.onWindowKeydown)
    this.input.removeEventListener("keydown", this.onInputKeydown)
    this.backdrop.removeEventListener("click", this.onBackdropClick)
    this.resultsEl.removeEventListener("click", this.onResultsClick)
    document.body.classList.remove("overflow-hidden")
  },

  handleWindowKeydown(event) {
    if (isToggleShortcut(event)) {
      event.preventDefault()
      this.isOpen() ? this.close() : this.open()
    } else if (event.key === "Escape" && this.isOpen()) {
      event.preventDefault()
      this.close()
    }
  },

  handleInputKeydown(event) {
    const items = this.items()
    const action = navAction(event.key, {
      activeIndex: this.activeIndex,
      count: items.length,
    })

    if (action.type === "none") return

    event.preventDefault()

    if (action.type === "move") {
      this.activeIndex = action.index
      this.highlight()
    } else if (action.type === "select") {
      const item = items[action.index]
      if (item) {
        this.close()
        item.click()
      }
    }
  },

  items() {
    return Array.from(this.resultsEl.querySelectorAll("[data-palette-item]"))
  },

  isOpen() {
    return !this.overlay.classList.contains("hidden")
  },

  open() {
    this.pushEventTo(this.el, "open", {})
  },

  close() {
    this.pushEventTo(this.el, "close", {})
  },

  highlight() {
    this.items().forEach((item, index) => {
      if (index === this.activeIndex) {
        item.classList.add(...ACTIVE_CLASSES)
        item.scrollIntoView({ block: "nearest" })
      } else {
        item.classList.remove(...ACTIVE_CLASSES)
      }
    })
  },
}
