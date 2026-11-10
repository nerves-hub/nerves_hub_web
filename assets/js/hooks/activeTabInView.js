// Brings the selected tab into view in a strip of tabs that scrolls sideways,
// as the organization's tabs do on a phone, and says when the strip is
// scrolled to its end.
//
// Each tab is its own LiveView, so moving to one swaps in a new strip, which
// starts scrolled to its left edge. Without this, choosing Certificates or
// Settings on a phone opens a page whose selected tab is off-screen.
//
// Only the strip is scrolled, never the page, and only when it is mounted: a
// strip someone has scrolled by hand is left where they put it.
//
// The strip fades out at its right edge to show there are more tabs. Once it
// is scrolled to the end there are none, so it carries `data-scrolled-to-end`
// and its classes drop the fade; otherwise the last tab, Settings, would sit
// half faded.

// Matches the strip's `mask-r-from-[calc(100%-2.5rem)]`: a tab under the fade
// at the right edge is not counted as in view.
const FADE = 40

// Where the strip should be scrolled to, or null to leave it. A tab already in
// full view, clear of the fade, stays where it is. Otherwise it is centred, so
// the tabs either side show too; the browser stops the scroll at the strip's
// ends.
//
// `tabStart` is how far the tab is from the start of the strip's content.
export function scrollLeftFor({
  tabStart,
  tabWidth,
  viewWidth,
  scrollLeft,
  fade = 0,
}) {
  const inView =
    tabStart >= scrollLeft &&
    tabStart + tabWidth <= scrollLeft + viewWidth - fade

  if (inView) return null

  return Math.max(0, Math.round(tabStart - (viewWidth - tabWidth) / 2))
}

// Whether the strip shows its last tab in full. Scroll positions can be a
// fraction of a pixel short of the end, so within a pixel counts.
export function atEnd({ scrollLeft, viewWidth, scrollWidth }) {
  return scrollLeft + viewWidth >= scrollWidth - 1
}

export default {
  mounted() {
    this.reveal()
    this.markEnd()
    this.el.addEventListener("scroll", () => this.markEnd(), { passive: true })
  },

  // A patch drops attributes the server did not render.
  updated() {
    this.markEnd()
  },

  reveal() {
    const strip = this.el
    const tab = strip.querySelector('[aria-current="page"]')

    // From md up every tab fits, and there is nothing to scroll.
    if (!tab || strip.scrollWidth <= strip.clientWidth) return

    const left = scrollLeftFor({
      tabStart:
        tab.getBoundingClientRect().left -
        strip.getBoundingClientRect().left +
        strip.scrollLeft,
      tabWidth: tab.getBoundingClientRect().width,
      viewWidth: strip.clientWidth,
      scrollLeft: strip.scrollLeft,
      fade: FADE,
    })

    if (left !== null) strip.scrollLeft = left
  },

  markEnd() {
    const strip = this.el

    strip.toggleAttribute(
      "data-scrolled-to-end",
      atEnd({
        scrollLeft: strip.scrollLeft,
        viewWidth: strip.clientWidth,
        scrollWidth: strip.scrollWidth,
      }),
    )
  },
}
