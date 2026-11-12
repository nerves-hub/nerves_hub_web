// The Console and System Shell on a phone. Tapping into the terminal opens the
// on-screen keyboard, which takes a third or more of the screen, so the
// terminal frame leaves the page and fills what the keyboard leaves visible:
// a bar naming the device with a Done button, the terminal, and a row of the
// keys a phone's keyboard lacks (Esc, Tab, Ctrl and the arrows).
//
// The mode is marked on `<html>` with `data-terminal-typing`, which the
// `terminal-typing:` variant in app.css reads, and the space the keyboard
// leaves is passed as `--terminal-top` and `--terminal-height`. Both live on
// `<html>` because a LiveView patch never touches it.
//
// Done, or anything else taking focus from the terminal, ends the mode.

const PHONE = "(max-width: 639.98px)"
const TYPING = "data-terminal-typing"

export const isPhone = () => window.matchMedia(PHONE).matches

const ARROWS = { up: "A", down: "B", right: "C", left: "D" }
const KEYS = { esc: "\x1b", tab: "\t" }

// What a key bar key sends. Arrows follow the terminal's cursor key mode, as
// a hardware keyboard's do: full-screen programs such as vi switch it on.
export const keySequence = (name, applicationCursorKeys = false) => {
  if (ARROWS[name]) return (applicationCursorKeys ? "\x1bO" : "\x1b[") + ARROWS[name]

  return KEYS[name] ?? null
}

// The character typed after Ctrl, as Ctrl held with it: Ctrl+C is 0x03, and
// Ctrl+? is DEL. Anything without a control code is sent as it is.
export const withControl = data => {
  if (data.length !== 1) return data
  if (data === "?") return "\x7f"

  const code = data.toUpperCase().charCodeAt(0)

  return code >= 64 && code <= 95 ? String.fromCharCode(code - 64) : data
}

// Returns `transform`, which the hook passes everything the terminal sends
// through (it applies a pressed Ctrl), and `teardown`.
export const setupPhoneKeyboard = ({ term, fitAddon, frame }) => {
  if (!frame) return { transform: data => data, teardown: () => {} }

  const root = document.documentElement
  const viewport = window.visualViewport
  const ctrlKey = frame.querySelector('[data-terminal-key="ctrl"]')
  let ctrl = false
  let fitRequest = null

  const setCtrl = on => {
    ctrl = on
    ctrlKey?.setAttribute("aria-pressed", String(on))
  }

  const refit = () => {
    if (fitRequest) cancelAnimationFrame(fitRequest)

    fitRequest = requestAnimationFrame(() => {
      fitRequest = null
      fitAddon.fit()
      term.scrollToBottom()
    })
  }

  // The keyboard shrinks the visual viewport, and iOS scrolls the page under
  // it, so the frame follows both.
  const place = () => {
    root.style.setProperty("--terminal-top", `${viewport ? viewport.offsetTop : 0}px`)
    root.style.setProperty("--terminal-height", `${viewport ? viewport.height : window.innerHeight}px`)
    refit()
  }

  const typing = () => root.hasAttribute(TYPING)

  const enter = () => {
    if (typing() || !isPhone()) return

    root.setAttribute(TYPING, "")
    place()
    viewport?.addEventListener("resize", place)
    viewport?.addEventListener("scroll", place)
  }

  const exit = () => {
    if (!typing()) return

    viewport?.removeEventListener("resize", place)
    viewport?.removeEventListener("scroll", place)
    root.removeAttribute(TYPING)
    root.style.removeProperty("--terminal-top")
    root.style.removeProperty("--terminal-height")
    setCtrl(false)
    refit()
  }

  const isTerminalInput = el => !!el && el === term.textarea

  const onFocusIn = event => {
    if (isTerminalInput(event.target)) enter()
  }

  // Focus can move to the terminal again straight away, after a key press.
  const onFocusOut = event => {
    if (!isTerminalInput(event.target)) return

    setTimeout(() => {
      if (!isTerminalInput(document.activeElement)) exit()
    }, 0)
  }

  // A key bar key or Done taking focus would close the keyboard.
  const keepFocus = event => {
    if (event.target.closest("[data-terminal-key], [data-terminal-done]")) event.preventDefault()
  }

  const press = name => {
    if (name === "ctrl") return setCtrl(!ctrl)

    const sequence = keySequence(name, term.modes.applicationCursorKeysMode)
    if (sequence) term.input(sequence, true)
  }

  const onClick = event => {
    const key = event.target.closest("[data-terminal-key]")

    if (key) {
      press(key.dataset.terminalKey)
      term.focus()
    } else if (event.target.closest("[data-terminal-done]")) {
      term.blur()
    }
  }

  frame.addEventListener("focusin", onFocusIn)
  frame.addEventListener("focusout", onFocusOut)
  frame.addEventListener("pointerdown", keepFocus)
  frame.addEventListener("mousedown", keepFocus)
  frame.addEventListener("click", onClick)

  const transform = data => {
    if (!ctrl) return data

    setCtrl(false)
    return withControl(data)
  }

  const teardown = () => {
    frame.removeEventListener("focusin", onFocusIn)
    frame.removeEventListener("focusout", onFocusOut)
    frame.removeEventListener("pointerdown", keepFocus)
    frame.removeEventListener("mousedown", keepFocus)
    frame.removeEventListener("click", onClick)
    if (fitRequest) cancelAnimationFrame(fitRequest)
    exit()
  }

  return { transform, teardown }
}
