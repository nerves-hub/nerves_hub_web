import { Socket } from "phoenix"
import { Terminal } from "@xterm/xterm"
import { WebglAddon } from "@xterm/addon-webgl"
import { WebLinksAddon } from "@xterm/addon-web-links"
import { FitAddon } from "@xterm/addon-fit"

const defaultTermOptions = {
  cursorBlink: true,
  cursorStyle: "bar",
  macOptionIsMeta: true,
  fontFamily: "Ubuntu Mono, courier-new, courier, monospace",
  fontSize: 14,
  theme: {
    foreground: "#FFFAF4",
    background: "#0E1019",
    selectionBackground: "#48B9C7",
    black: "#232323",
    brightBlack: "#444444",
    red: "#D82036",
    brightRed: "#FF2740",
    green: "#8CE10B",
    brightGreen: "#ABE15B",
    yellow: "#FFB900",
    brightYellow: "#FFD242",
    blue: "#007AD8",
    brightBlue: "#0092FF",
    magenta: "#6D43A6",
    brightMagenta: "#9A5FEB",
    cyan: "#00D8EB",
    brightCyan: "#67FFF0",
    white: "#FFFFFF",
    brightWhite: "#FFFFFF"
  }
}

const debounce = (func, time = 100) => {
  let timer
  return function(event) {
    if (timer) clearTimeout(timer)
    timer = setTimeout(func, time, event)
  }
}

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

    const deviceId = this.el.dataset.deviceId
    const channel = this.socket.channel(`user:local_shell:${deviceId}`, {})

    // init terminal, load addons
    // use previous scrollback if available, default to 1000 lines
    const storedScrollback = parseInt(localStorage.getItem("scrollback"))
    const scrollback = Number.isSafeInteger(storedScrollback)
      ? storedScrollback
      : 1000

    const term = new Terminal({ ...defaultTermOptions, scrollback })

    const fitAddon = new FitAddon()
    term.loadAddon(fitAddon)
    term.loadAddon(new WebglAddon())
    term.loadAddon(new WebLinksAddon())

    term.open(document.getElementById("local-shell"))

    fitAddon.fit()
    term.focus()

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
    this.socket.disconnect()
  }
}
