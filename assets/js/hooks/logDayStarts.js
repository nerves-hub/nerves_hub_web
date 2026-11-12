// Marks the first line of each day in a list of log lines, so CSS can show the
// day's heading above it.
//
// Lines stream in at the top as the device sends them and older pages are added
// at the bottom, so the server cannot know which line starts a day: the line
// that does can change after it was sent. Each line carries its day in
// `data-day`, and this sets `data-day-start` on every line whose day differs
// from the one above it, whenever the list changes.
export function dayStarts(days) {
  return days.map((day, index) => index === 0 || days[index - 1] !== day)
}

export default {
  mounted() {
    this.mark()
    this.observer = new MutationObserver(() => this.mark())
    this.observer.observe(this.el, { childList: true })
  },

  destroyed() {
    this.observer.disconnect()
  },

  mark() {
    const lines = Array.from(this.el.children)
    const starts = dayStarts(lines.map((line) => line.dataset.day))

    lines.forEach((line, index) =>
      line.toggleAttribute("data-day-start", starts[index]),
    )
  },
}
