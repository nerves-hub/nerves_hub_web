// Asks the server for more of a list when this element scrolls into view, or is
// clicked, and gets out of the way once there is no more to ask for.
//
// Put it on the "Show more" button at the bottom of a list, with the event to
// send in `data-event` and the id of the list it sits under in `data-list`. The
// server decides what "more" is and drops the button when it runs out, which
// ends the hook with it.
//
// An IntersectionObserver rather than `phx-viewport-bottom`: that one only
// fires while the user is scrolling, so a first page that does not fill the
// screen has no scroll to trigger it, and it looks for the nearest scrolling
// ancestor itself where an observer works whichever element does the scrolling.
export default {
  mounted() {
    this.loading = false
    this.revealAfter = null

    this.onClick = () => this.load({ reveal: true })
    this.el.addEventListener("click", this.onClick)

    this.observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((entry) => entry.isIntersecting)) this.load()
      },
      // Start a little before the button is actually reached, so a page is
      // usually there by the time the user is.
      { rootMargin: "0px 0px 200px 0px" },
    )
    this.observer.observe(this.el)
  },

  // A page has arrived. An observer only reports a change, so if the button is
  // still on screen (a page that did not push it out of view) it would never
  // say so again; observing afresh makes it report where the button is now.
  updated() {
    this.loading = false
    this.observer.unobserve(this.el)
    this.observer.observe(this.el)
    this.revealNewLines()
  },

  destroyed() {
    this.observer.disconnect()
    this.el.removeEventListener("click", this.onClick)
  },

  load({ reveal = false } = {}) {
    // One request at a time, whichever of the scroll and the click got here first.
    if (this.loading) return
    this.loading = true
    this.el.setAttribute("data-loading", "")

    // Where the list ends now, so the first line added after it can be found.
    // Set on every load, not only a click's, so a click that changed nothing
    // cannot leave one behind for a later scroll to act on.
    this.revealAfter = reveal
      ? document.getElementById(this.el.dataset.list)?.lastElementChild
      : null

    this.pushEvent(this.el.dataset.event, {}, () => {
      // Also cleared here in case the reply changed nothing on the page, which
      // would leave `updated` uncalled and the button stuck.
      this.loading = false
      this.el.removeAttribute("data-loading")
    })
  },

  // After a click the new lines are all below the fold and the button that was
  // clicked has gone down with them, so nothing on screen has changed and it
  // looks as if nothing happened. Bring the first new line to the top. Not after
  // a scroll, where the user is already on their way down.
  revealNewLines() {
    const first = this.revealAfter?.nextElementSibling
    this.revealAfter = null
    if (!first) return

    const scroller = this.el.parentElement
    const offset =
      first.getBoundingClientRect().top - scroller.getBoundingClientRect().top
    const reduceMotion = window.matchMedia(
      "(prefers-reduced-motion: reduce)",
    ).matches

    scroller.scrollTo({
      top: scroller.scrollTop + offset,
      behavior: reduceMotion ? "auto" : "smooth",
    })
  },
}
