// The keys of the devices list's peek panel (NervesHubWeb.Components.DevicePeek):
// ↑ and ↓ peek at the previous and next device, ↵ opens the device, esc closes
// the panel. The hook is on the panel, so the keys only work while it's open.

const TYPING = "input, textarea, select, [contenteditable]:not([contenteditable='false'])"
const ACTIVATES_ON_ENTER = "a[href], button, summary, [role='button']"

// What a keydown does, or null to leave it to the browser. Keys with a
// modifier are someone else's shortcut, and keys typed into a field are text.
// While one of the bulk bar's popovers is open, the keys are its own.
export function peekKeyAction(event, { popoverOpen = false } = {}) {
  if (popoverOpen) return null
  if (event.metaKey || event.ctrlKey || event.altKey || event.shiftKey) return null
  if (event.defaultPrevented || event.isComposing) return null

  const target = event.target
  if (target && target.closest && target.closest(TYPING)) return null

  switch (event.key) {
    case "ArrowDown":
      return { type: "move", by: 1 }
    case "ArrowUp":
      return { type: "move", by: -1 }
    case "Escape":
      return { type: "close" }
    case "Enter":
      // A focused link or button already does something with Enter.
      if (target && target.closest && target.closest(ACTIVATES_ON_ENTER)) return null
      return { type: "open" }
    default:
      return null
  }
}

export default {
  mounted() {
    this.controller = new AbortController()

    window.addEventListener(
      "keydown",
      (event) => {
        const popoverOpen = !!document.getElementById("bulk-popover")
        const action = peekKeyAction(event, { popoverOpen })
        if (!action) return

        event.preventDefault()

        if (action.type === "move") this.pushEvent("peek-move", { by: action.by })
        if (action.type === "close") this.pushEvent("close-peek", {})
        if (action.type === "open") this.el.querySelector("[data-peek-open]")?.click()
      },
      { signal: this.controller.signal },
    )

    this.revealRow()
  },

  updated() {
    if (this.el.dataset.deviceId !== this.shownId) this.revealRow()
  },

  destroyed() {
    this.controller.abort()
  },

  // Keeps the peeked row in view as the arrow keys move down the list.
  revealRow() {
    this.shownId = this.el.dataset.deviceId
    document.getElementById(`device-row-${this.shownId}`)?.scrollIntoView({ block: "nearest" })
  },
}
