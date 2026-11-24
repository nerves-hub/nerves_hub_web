// The connection lane on the device Health tab. Hovering an offline span (or
// focusing it) darkens the charts' matching Offline bands while the CSS
// tooltip shows; tapping one selects it, which on a phone opens its detail
// under the lane, and keeps the bands dark until it's tapped again.
//
// Each offline span is a button carrying:
//   data-offline-span   a key that stays the same across updates
//   data-from / data-until   the part of it the lane shows, in unix ms
// and its detail, when there's one, is the element with the same key in
// `data-offline-detail`.
//
// The charts hear about it as a `offlineHighlighted` window event whose detail
// is `{ period: [from, until] }`, or `{ period: null }` to clear it.

// What the charts should show darkened: what's under the pointer, else what's
// selected, else nothing.
export function highlightedKey(hovered, selected) {
  return hovered ?? selected ?? null
}

// Tapping a selected span clears it; tapping another moves to it.
export function toggle(selected, key) {
  return selected === key ? null : key
}

// Whether two [from, until] spans overlap, for the charts to find the bands
// that match a span on the lane, which may be cut to a different range.
export function overlaps([from, until], [otherFrom, otherUntil]) {
  return from < otherUntil && otherFrom < until
}

export default {
  mounted() {
    this.hovered = null
    this.selected = null

    this.onOver = (event) => {
      const span = event.target.closest("[data-offline-span]")
      if (!span || event.pointerType === "touch") return

      this.hovered = span.dataset.offlineSpan
      this.apply()
    }

    this.onOut = (event) => {
      const span = event.target.closest("[data-offline-span]")
      if (!span || span.contains(event.relatedTarget)) return

      this.hovered = null
      this.apply()
    }

    this.onClick = (event) => {
      const span = event.target.closest("[data-offline-span]")
      if (!span) return

      this.selected = toggle(this.selected, span.dataset.offlineSpan)
      this.apply()
    }

    this.el.addEventListener("pointerover", this.onOver)
    this.el.addEventListener("pointerout", this.onOut)
    this.el.addEventListener("focusin", this.onOver)
    this.el.addEventListener("focusout", this.onOut)
    this.el.addEventListener("click", this.onClick)
  },

  // The server redraws the lane every minute and on every zoom, which resets
  // the buttons and hides every detail, so the selection is put back. A span
  // that has gone from the lane can't stay selected.
  updated() {
    if (this.selected && !this.span(this.selected)) this.selected = null
    if (this.hovered && !this.span(this.hovered)) this.hovered = null
    this.apply()
  },

  destroyed() {
    this.broadcast(null)
  },

  span(key) {
    return this.el.querySelector(`[data-offline-span="${CSS.escape(key)}"]`)
  },

  apply() {
    for (const button of this.el.querySelectorAll("[data-offline-span]")) {
      button.setAttribute("aria-pressed", String(button.dataset.offlineSpan === this.selected))
    }

    for (const detail of this.el.querySelectorAll("[data-offline-detail]")) {
      detail.style.display = detail.dataset.offlineDetail === this.selected ? "" : "none"
    }

    const key = highlightedKey(this.hovered, this.selected)
    const span = key && this.span(key)
    this.broadcast(span ? [Number(span.dataset.from), Number(span.dataset.until)] : null)
  },

  broadcast(period) {
    window.dispatchEvent(new CustomEvent("offlineHighlighted", { detail: { period } }))
  },
}
