import { Terminal } from "xterm"
import { WebglAddon } from "xterm-addon-webgl"
import { WebLinksAddon } from "xterm-addon-web-links"
import { FitAddon } from "xterm-addon-fit"

const defaultTermOptions = {
  disableStdin: true,
  cursorBlink: true,
  cursorStyle: "bar",
  macOptionIsMeta: true,
  fontFamily: "Ubuntu Mono, courier-new, courier, monospace",
  fontSize: 14,
  rows: 20,
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

export default {
  mounted() {
    let content = document.getElementById("support-script-output").textContent
    let contentRows = content.split("\n")

    if (contentRows.length <= 20) {
      defaultTermOptions["rows"] = contentRows.length + 1
    }

    const term = new Terminal(defaultTermOptions)

    term.loadAddon(new WebglAddon())
    term.loadAddon(new WebLinksAddon())

    term.open(this.el)

    term.writeln(contentRows.join("\n\r"))
  }
}
