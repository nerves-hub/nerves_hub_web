// On a phone the whole device page scrolls, header and all, under tabs that
// stick to the top. Once the header has scrolled away, the top bar shows the
// device in its place (see `Header.compact_bar/1`), so you still know which
// device you are on.
//
// This marks `<html>` with `data-device-header-scrolled` then, which the
// `header-scrolled:` variant in app.css reads. It is set on `<html>` because
// the top bar belongs to the layout, outside this element, and because a
// LiveView patch never touches `<html>`'s attributes.
//
// Switching tabs while scrolled down keeps the tabs where they are and starts
// the new tab at its top, rather than somewhere down its length.
//
// From `sm` up only the tab's content scrolls, so this element never does and
// the mark is never set.

const ATTRIBUTE = "data-device-header-scrolled"

export default {
  mounted() {
    this.tab = this.el.dataset.tab
    this.frame = null

    this.onScroll = () => {
      if (this.frame) return

      this.frame = requestAnimationFrame(() => {
        this.frame = null
        this.mark()
      })
    }

    this.el.addEventListener("scroll", this.onScroll, { passive: true })
    this.mark()
  },

  updated() {
    if (this.el.dataset.tab !== this.tab) {
      this.tab = this.el.dataset.tab

      const overhang = this.overhang()
      if (overhang !== null && overhang < 0) this.el.scrollTop += overhang
    }

    this.mark()
  },

  destroyed() {
    if (this.frame) cancelAnimationFrame(this.frame)
    document.documentElement.removeAttribute(ATTRIBUTE)
  },

  // How far the header's bottom edge is below the top of this element: zero or
  // less once it has scrolled out of sight.
  overhang() {
    const header = this.el.querySelector("#device-header")
    if (!header) return null

    return (
      header.getBoundingClientRect().bottom -
      this.el.getBoundingClientRect().top
    )
  },

  mark() {
    const overhang = this.overhang()
    const scrolled = overhang !== null && overhang <= 0

    document.documentElement.toggleAttribute(ATTRIBUTE, scrolled)
  },
}
