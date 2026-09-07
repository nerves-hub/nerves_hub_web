// Generic "copy to clipboard" hook.
//
// Copies the string in the element's `data-copy-value` attribute to the
// clipboard when clicked. If the button contains icons tagged with
// `data-icon="copy"` and `data-icon="check"`, it briefly swaps the copy icon
// for the check icon to confirm the copy.
export default {
  mounted() {
    this.handleClick = () => this.copy(this.el.dataset.copyValue ?? "")
    this.el.addEventListener("click", this.handleClick)
  },

  destroyed() {
    this.el.removeEventListener("click", this.handleClick)
    clearTimeout(this.resetTimeout)
  },

  copy(text) {
    const confirmCopied = () => this.flash()

    if (typeof ClipboardItem !== "undefined" && navigator.clipboard?.write) {
      // NOTE: Safari locks down the clipboard API to only work when triggered
      //   by a direct user interaction and won't allow it inside an async
      //   promise. Wrapping the value in a ClipboardItem works around this.
      const type = "text/plain"
      const blob = new Blob([text], { type })
      const data = [new window.ClipboardItem({ [type]: blob })]
      navigator.clipboard.write(data).then(confirmCopied, () => {})
    } else if (navigator.clipboard?.writeText) {
      navigator.clipboard.writeText(text).then(confirmCopied, () => {})
    }
  },

  flash() {
    const copyIcon = this.el.querySelector("[data-icon='copy']")
    const checkIcon = this.el.querySelector("[data-icon='check']")

    if (!copyIcon || !checkIcon) return

    copyIcon.classList.add("hidden")
    checkIcon.classList.remove("hidden")

    clearTimeout(this.resetTimeout)
    this.resetTimeout = setTimeout(() => {
      copyIcon.classList.remove("hidden")
      checkIcon.classList.add("hidden")
    }, 1500)
  },
}
