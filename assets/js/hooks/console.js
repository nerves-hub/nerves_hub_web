import { acceptsFiles } from "../helpers/consoleFiles.js"
import {
  connectUserSocket,
  createTerminal,
  debounce,
  setupOptionAsMetaToggle
} from "../helpers/terminal.js"

const resizeContent = (term, channel) => {
  channel.push("window_size", { height: term.rows, width: term.cols })
}

export default {
  mounted() {
    // socket + channel setup to receive device console data
    this.socket = connectUserSocket()

    const deviceIdentifier = this.el.dataset.deviceIdentifier
    const channel = this.socket.channel(
      `user:console:identifier-${deviceIdentifier}`,
      {},
    )

    const { term, fitAddon } = createTerminal("console")

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
        channel.push("window_size", { height: term.rows, width: term.cols })
      })
      .receive("error", () => {
        console.log("ERROR")
      })
    // Stream all events straight to the device
    term.onData(data => {
      channel.push("dn", { data })
    })

    // The device's console version, which says whether it can take a file.
    // It arrives once the device's console answers, so it may be unknown.
    let consoleVersion = null

    channel.on("metadata", payload => {
      consoleVersion = payload.version
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
        this.resizeEventListener()
        resizeContent.apply(null, [term, channel])
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

      e.dataTransfer.dropEffect = acceptsFiles(consoleVersion) ? "copy" : "none"
    })

    dropzone.addEventListener(
      "drop",
      e => {
        e.preventDefault()
        e.stopPropagation()
        if (!acceptsFiles(consoleVersion)) return
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
  },
  destroyed() {
    window.removeEventListener("resize", this.resizeEventListener)
    this.teardownOptionAsMetaToggle()
    this.socket.disconnect()
  }
}
