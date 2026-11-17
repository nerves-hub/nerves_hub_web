// The Needs attention list (NervesHubWeb.Live.Devices.Index). On a screen wide
// enough to dock the peek beside the list, it opens the first device in the
// peek, so the list reads as a list and its detail.
//
// It does so once for each list it's shown: on arriving at the tab, and again
// when `data-key` changes, which it does when a different list loads (another
// reason, query, filter or page). A refresh of the same list, or a peek
// someone closed, is left alone.

const WIDE = "(min-width: 64rem)"

// Whether to open the first device: the list has changed since it last did,
// the screen is wide, and nothing is open already (the peek, or the Filters
// panel, which a peek would open underneath).
export function shouldOpenFirst({ key, openedKey, wide, peekOpen, filtersOpen, firstId }) {
  return key !== openedKey && wide && !peekOpen && !filtersOpen && Boolean(firstId)
}

export default {
  mounted() {
    this.openedKey = null
    this.openFirst()
  },

  updated() {
    this.openFirst()
  },

  openFirst() {
    const key = this.el.dataset.key
    const first = this.el.querySelector("li[id^='device-row-']")
    const firstId = first?.id.replace("device-row-", "")

    if (
      shouldOpenFirst({
        key,
        openedKey: this.openedKey,
        wide: window.matchMedia(WIDE).matches,
        peekOpen: Boolean(document.getElementById("device-peek")),
        filtersOpen: Boolean(document.getElementById("filter-panel")),
        firstId,
      })
    ) {
      this.pushEvent("peek", { id: firstId })
    }

    this.openedKey = key
  },
}
