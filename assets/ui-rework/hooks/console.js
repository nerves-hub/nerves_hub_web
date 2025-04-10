import { Socket } from "phoenix"
import { Terminal } from "xterm"
import { WebglAddon } from "xterm-addon-webgl"
import { WebLinksAddon } from "xterm-addon-web-links"
import { FitAddon } from "xterm-addon-fit"
import semver from "semver"

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

const resizeContent = (term, fitAddon) => {
  term.resize(5, 5)
  fitAddon.fit()
}

export default {
  mounted() {
    // socket + channel setup to receive device console data
    const socket = new Socket("/socket", {
      params: { token: this.el.dataset.userToken }
    })
    socket.connect()

    const deviceId = this.el.dataset.deviceId
    const channel = socket.channel(`user:console:${deviceId}`, {})

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

    term.open(document.getElementById("console"))

    fitAddon.fit()
    term.focus()

    // resize terminal on window resize
    window.addEventListener(
      "resize",
      debounce(() => {
        resizeContent.apply(null, [term, fitAddon])
      }, 300)
    )

    channel
      .join()
      .receive("ok", () => {
        // This will be the same for everyone, the first time it should be used
        // and there after it will be ignored as a noop by erlang
        channel.push("window_size", { height: term.rows, width: term.cols })
      })
      .receive("error", () => {
        console.log("ERROR")
      })
    // Stream all events straight to the device
    term.onData(data => {
      channel.push("dn", { data })
    })

    // Write data from device to console
    channel.on("up", payload => {
      term.write(payload.data)
    })

    let downloadingFileBuffer = []

    channel.on("file-data/start", () => {
      downloadingFileBuffer = []
    })

    channel.on("file-data", payload => {
      const data = atob(payload.data)

      const buffer = new Uint8Array(data.length)

      for (var i = 0; i < data.length; i++) {
        buffer[i] = data.charCodeAt(i)
      }

      downloadingFileBuffer.push(buffer)
    })

    channel.on("file-data/stop", payload => {
      let length = 0

      for (let i in downloadingFileBuffer) {
        let buffer = downloadingFileBuffer[i]
        length += buffer.length
      }

      const mainBuffer = new Uint8Array(length)

      let offset = 0

      for (let i in downloadingFileBuffer) {
        let buffer = downloadingFileBuffer[i]
        mainBuffer.set(buffer, offset)
        offset += buffer.length
      }

      const file = new Blob([mainBuffer])

      const link = document.createElement("a")
      const url = URL.createObjectURL(file)

      link.href = url
      link.download = payload.filename
      document.body.appendChild(link)
      link.click()

      document.body.removeChild(link)
      window.URL.revokeObjectURL(url)
    })

    // Set new size on device when window changes
    window.addEventListener("resize", () => {
      term.scrollToBottom()
    })

    document.getElementById("fullscreen").addEventListener("click", () => {
      // put this on the next tick instead of immediate just to reduce risk of racing
      window.setTimeout(() => {
        fitAddon.fit()
        term.scrollToBottom()
        term.focus()
      }, 1000)
    })

    channel.onClose(() => {
      term.blur()
      term.setOption("cursorBlink", false)
      term.write("DISCONNECTED")
    })

    let dropzone = document.getElementById("dropzone")

    dropzone.addEventListener("dragover", function(e) {
      e.stopPropagation()
      e.preventDefault()

      if (semver.gte(metadata.version, "2.0.0")) {
        e.dataTransfer.dropEffect = "copy"
      } else {
        e.dataTransfer.dropEffect = "none"
      }
    })

    dropzone.addEventListener(
      "drop",
      e => {
        e.preventDefault()
        e.stopPropagation()
        if (e.dataTransfer.items) {
          for (const item of e.dataTransfer.items) {
            const file = item.getAsFile()
            const reader = file.stream().getReader()

            channel.push("file-data/start", { filename: file.name })

            reader.read().then(function process({ done, value }) {
              if (done) {
                channel.push("file-data/stop", { filename: file.name })
                return
              }

              const chunkSize = 1024
              let chunkNum = 0

              for (let i = 0; i < value.length; i += chunkSize) {
                const chunk = value.slice(i, i + chunkSize)

                const encoded = btoa(String.fromCharCode.apply(null, chunk))

                channel.push("file-data", {
                  filename: file.name,
                  chunk: chunkNum,
                  data: encoded
                })

                chunkNum += 1
              }

              return reader.read().then(process)
            })
          }
        }
      },
      false
    )
  }
}
