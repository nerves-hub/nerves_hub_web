// A one-time code typed into a row of single-digit slots.
//
// The slots are drawn; the typing goes into one real <input> laid over them,
// so pasting a whole code, the browser's one-time-code autofill and password
// managers all work as they would on a plain field. Without JavaScript the
// input shows as a plain text field and the slots stay hidden, which is also
// why the server renders it without a maxlength: a recovery code is longer.
//
// Markup (see `NervesHubWeb.Components.OtpInput`):
//
//   <div data-otp-input data-otp-autosubmit="true">
//     <input data-otp-field ... />
//     <div data-otp-slots>
//       <div data-otp-slot><span data-otp-char></span><span data-otp-caret></span></div>
//       ...
//     </div>
//   </div>
//
// Works on a page LiveView doesn't run (the sign-in pages) through
// `mountAll`, and inside a LiveView through the `OtpInput` hook.

// Digits only, at most `length` of them. Pasted codes often carry a space
// ("482 913") or a dash, and an autofilled one can arrive with whitespace.
export function normalizeCode(value, length) {
  return (value || "").replace(/\D/g, "").slice(0, length)
}

// Which slot the caret is in: the next empty one, or the last when full.
export function activeSlot(code, length) {
  return Math.min(code.length, length - 1)
}

export function mount(el) {
  if (el._otpRender) return el._otpRender()
  const field = el.querySelector("[data-otp-field]")
  const slots = Array.from(el.querySelectorAll("[data-otp-slot]"))
  const length = slots.length
  if (!field || length === 0) return

  let submitted = null

  const render = () => {
    // Set here rather than once: a LiveView patch puts back what the server
    // rendered, which has none of these.
    el.dataset.otpReady = "true"
    field.setAttribute("maxlength", String(length))
    field.setAttribute("inputmode", "numeric")
    field.setAttribute("pattern", `[0-9]{${length}}`)

    const code = normalizeCode(field.value, length)
    if (field.value !== code) field.value = code

    const focused = document.activeElement === field
    const active = activeSlot(code, length)

    slots.forEach((slot, i) => {
      const char = slot.querySelector("[data-otp-char]")
      const next = code[i] || ""

      if (char && char.textContent !== next) {
        char.textContent = next
        // Restart the pop for a digit that just arrived.
        if (next) {
          slot.removeAttribute("data-otp-popped")
          void slot.offsetWidth
          slot.setAttribute("data-otp-popped", "")
        }
      }

      slot.toggleAttribute("data-otp-filled", next !== "")
      slot.toggleAttribute("data-otp-active", focused && i === active)
      slot.toggleAttribute("data-otp-caret-on", focused && i === active && next === "")
    })

    if (el.dataset.otpAutosubmit === "true" && code.length === length && submitted !== code && field.form) {
      submitted = code
      field.form.requestSubmit()
    }
  }

  // Typing after a wrong code starts again, rather than keeping the error.
  const clearInvalid = () => el.removeAttribute("data-otp-invalid")

  // The caret always sits at the end; there is nothing to edit in the middle.
  const keepCaretAtEnd = () => {
    const end = field.value.length
    field.setSelectionRange(end, end)
  }

  field.addEventListener("input", () => {
    clearInvalid()
    render()
  })
  field.addEventListener("focus", () => {
    keepCaretAtEnd()
    render()
  })
  field.addEventListener("blur", render)
  field.addEventListener("select", keepCaretAtEnd)
  field.addEventListener("click", keepCaretAtEnd)

  el._otpRender = render
  render()
}

export function mountAll(root = document) {
  root.querySelectorAll("[data-otp-input]").forEach(mount)
}

// Swaps a page between the code from an app and a recovery code. Each half is
// a `[data-otp-mode]` panel, within the toggle's `[data-otp-modes]` (or the
// whole page); the one hidden has its inputs disabled so only
// the other is sent. The toggles are links to the same page in the other
// mode, so they still work without JavaScript; this only saves the reload.
export function mountModeToggles(root = document) {
  root.querySelectorAll("[data-otp-mode-toggle]").forEach((button) => {
    if (button.dataset.otpToggleReady) return
    button.dataset.otpToggleReady = "true"

    button.addEventListener("click", (event) => {
      event.preventDefault()
      const scope = button.closest("[data-otp-modes]") || document
      const want = button.dataset.otpModeToggle

      // An error was about a code typed into the other field.
      scope.querySelectorAll("[data-otp-error]").forEach((error) => error.remove())
      scope.querySelectorAll("[data-otp-invalid]").forEach((field) => field.removeAttribute("data-otp-invalid"))

      scope.querySelectorAll("[data-otp-mode]").forEach((panel) => {
        const show = panel.dataset.otpMode === want
        panel.hidden = !show
        panel.querySelectorAll("input").forEach((input) => (input.disabled = !show))
      })

      scope.querySelector(`[data-otp-mode="${want}"] input:not([type=hidden])`)?.focus()
    })
  })
}

export const OtpInputHook = {
  mounted() {
    mount(this.el)
  },
  updated() {
    mount(this.el)
  },
}
