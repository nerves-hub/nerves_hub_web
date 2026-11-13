import { Socket } from "phoenix"
import { Terminal } from "@xterm/xterm"
import { WebglAddon } from "@xterm/addon-webgl"
import { WebLinksAddon } from "@xterm/addon-web-links"
import { FitAddon } from "@xterm/addon-fit"
import { whenFontsLoaded } from "./fonts.js"

// `macOptionIsMeta` is only honoured on a Mac, so mirror xterm's own platform
// check rather than showing a toggle that does nothing everywhere else.
const isMac = () =>
  ["Macintosh", "MacIntel", "MacPPC", "Mac68K"].includes(navigator.platform)

// Stored per browser rather than per account: which modifier Option is depends
// on the keyboard you're sitting at, not on who you're signed in as.
const OPTION_AS_META_KEY = "terminalOptionAsMeta"

const optionAsMeta = () => localStorage.getItem(OPTION_AS_META_KEY) === "true"

// JetBrains Mono is the app's `--font-mono` (see app.css). xterm draws on a
// canvas, so it is named here too.
export const TERMINAL_FONT_FAMILY =
  '"JetBrains Mono", Ubuntu Mono, courier-new, courier, monospace'

// The faces xterm draws with: regular text, and bold for bold ANSI output.
export const TERMINAL_FONTS = [
  `14px ${TERMINAL_FONT_FAMILY}`,
  `bold 14px ${TERMINAL_FONT_FAMILY}`
]

const defaultTermOptions = {
  cursorBlink: true,
  cursorStyle: "bar",
  // Option is the third-level shift on most non-US Mac layouts, so leaving it
  // alone is what keeps `[ ] { } | @ \ ~` typeable. Claiming it as Meta routes
  // the keypress through xterm's US-only keycode table instead, which turns
  // German Opt+5 into `ESC 5` rather than `[`. Users who'd rather have `M-b`
  // and `M-f` opt back in with the toggle above the terminal.
  macOptionIsMeta: false,
  fontFamily: TERMINAL_FONT_FAMILY,
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

// The console and local shell socket signs in with the session cookie, as the
// LiveView socket does, so it sends the page's CSRF token the same way.
export const connectUserSocket = () => {
  const csrfToken = document
    .querySelector("meta[name='csrf-token']")
    .getAttribute("content")

  const socket = new Socket("/socket", { params: { _csrf_token: csrfToken } })
  socket.connect()

  return socket
}

export const debounce = (func, time = 100) => {
  let timer
  return function(event) {
    if (timer) clearTimeout(timer)
    timer = setTimeout(func, time, event)
  }
}

// Builds the terminal shared by the device console and the local shell, opens
// it in `elementId` and sizes it to the container. It opens once JetBrains Mono
// has loaded, since xterm measures its cells then. Until it opens, anything
// written to it is kept and shown when it does, and `fitAddon.fit()` does
// nothing.
export const createTerminal = elementId => {
  // use previous scrollback if available, default to 1000 lines
  const storedScrollback = parseInt(localStorage.getItem("scrollback"))
  const scrollback = Number.isSafeInteger(storedScrollback)
    ? storedScrollback
    : 1000

  const term = new Terminal({
    ...defaultTermOptions,
    scrollback,
    macOptionIsMeta: optionAsMeta()
  })

  const fitAddon = new FitAddon()
  term.loadAddon(fitAddon)
  term.loadAddon(new WebglAddon())
  term.loadAddon(new WebLinksAddon())

  const container = document.getElementById(elementId)

  whenFontsLoaded(TERMINAL_FONTS, () => {
    // The hook may have been torn down while the font loaded.
    if (!container.isConnected) return

    term.open(container)
    fitAddon.fit()
    term.focus()
  })

  return { term, fitAddon }
}

// The toggle renders hidden and is only revealed on a Mac. xterm reads
// `macOptionIsMeta` on every keystroke, so flipping it applies straight away
// without reconnecting the channel. Returns a teardown function.
export const setupOptionAsMetaToggle = term => {
  const toggle = document.getElementById("option-as-meta")

  if (!toggle || !isMac()) return () => {}

  toggle.checked = optionAsMeta()
  toggle.closest("label").classList.replace("hidden", "flex")

  const onChange = () => {
    localStorage.setItem(OPTION_AS_META_KEY, toggle.checked)
    term.options.macOptionIsMeta = toggle.checked
    term.focus()
  }

  toggle.addEventListener("change", onChange)

  return () => toggle.removeEventListener("change", onChange)
}
