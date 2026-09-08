import { Socket } from "phoenix"
import {
  createTerminal,
  debounce,
  setupOptionAsMetaToggle
} from "../helpers/terminal.js"

const resizeContent = (term, channel) => {
  channel.push("window_size", { rows: term.rows, cols: term.cols })
}

export default {
  mounted() {
    // socket + channel setup to receive device console data
    this.socket = new Socket("/socket", {
      params: { token: this.el.dataset.userToken }
    })
    this.socket.connect()

    const deviceIdentifier = this.el.dataset.deviceIdentifier
    const channel = this.socket.channel(
      `user:local_shell:identifier-${deviceIdentifier}`,
      {},
    )

    const { term, fitAddon } = createTerminal("local-shell")

    this.teardownOptionAsMetaToggle = setupOptionAsMetaToggle(term)

    this.resizeEventListener = () => {
      fitAddon.fit()
      term.scrollToBottom()
      term.focus()
    }

    // resize terminal on window resize
    window.addEventListener("resize", this.resizeEventListener)

    term.onResize(
      debounce(() => {
        resizeContent.apply(null, [term, channel])
      }, 500)
    )

    channel
      .join()
      .receive("ok", () => {
        // This will be the same for everyone, the first time it should be used
        // and there after it will be ignored as a noop by erlang
        channel.push("window_size", { rows: term.rows, cols: term.cols })
      })
      .receive("error", () => {
        console.log("ERROR")
      })
    // Stream all events straight to the device
    term.onData(data => {
      channel.push("input", { data })
    })

    // Write data from device to console
    channel.on("output", payload => {
      term.write(payload.data)
    })

    document.getElementById("fullscreen").addEventListener("click", () => {
      // put this on the next tick instead of immediate just to reduce risk of racing
      window.setTimeout(() => {
        this.resizeEventListener()
        resizeContent.apply(null, [term, channel])
      }, 1000)
    })

    channel.onClose(() => {
      term.blur()
      term.setOption("cursorBlink", false)
      term.write("DISCONNECTED")
    })
  },
  destroyed() {
    window.removeEventListener("resize", this.resizeEventListener)
    this.teardownOptionAsMetaToggle()
    this.socket.disconnect()
  }
}
