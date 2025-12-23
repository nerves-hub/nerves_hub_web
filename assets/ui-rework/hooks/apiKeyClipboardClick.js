export default {
  mounted() {
    const parent = this.el
    this.el.addEventListener("click", () => {
      const apiKey = document.getElementById("api-key-" + parent.value)
        .value
      if (typeof ClipboardItem && navigator.clipboard.write) {
        // NOTE: Safari locks down the clipboard API to only work when triggered
        //   by a direct user interaction. You can't use it async in a promise.
        //   But! You can wrap the promise in a ClipboardItem, and give that to
        //   the clipboard API.
        //   Found this on https://developer.apple.com/forums/thread/691873

        const type = "text/plain"
        const blob = new Blob([apiKey], { type })
        const data = [new window.ClipboardItem({ [type]: blob })]
        navigator.clipboard.write(data)

        confirm("API Key copied to your clipboard")
      } else {
        // NOTE: Firefox has support for ClipboardItem and navigator.clipboard.write,
        //   but those are behind `dom.events.asyncClipboard.clipboardItem` preference.
        //   Good news is that other than Safari, Firefox does not care about
        //   Clipboard API being used async in a Promise.
        navigator.clipboard.writeText(apiKey)
        confirm("API Key copied to your clipboard")
      }
    })
  }
}
