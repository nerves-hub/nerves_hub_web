// Tokenizer/suggestion engine for the device list advanced search box.
//
// This is a *cosmetic and UX* layer only: it drives syntax highlighting and
// autosuggest in the contenteditable box. The server (`NervesHub.Devices.AdvancedQuery`)
// is the single source of truth for whether a query is actually valid -
// this tokenizer is intentionally looser and simpler than the Elixir lexer/parser.

// Multi-character symbols must precede their single-character prefixes so the
// longest match wins (e.g. ">=" before ">").
const SYMBOLS = ["!=", ">=", "<=", "=", ">", "<", "(", ")"]
// `:` is included so the `metric:<key>` column syntax tokenizes as one ident.
const IDENT_RE = /[A-Za-z0-9_.:-]/

function tokenize(text) {
  const tokens = []
  let i = 0
  const len = text.length

  while (i < len) {
    const start = i
    const ch = text[i]

    if (/\s/.test(ch)) {
      while (i < len && /\s/.test(text[i])) i++
      tokens.push({
        type: "whitespace",
        value: text.slice(start, i),
        start,
        end: i,
      })
      continue
    }

    if (ch === '"') {
      i++
      let closed = false
      while (i < len) {
        if (text[i] === "\\" && i + 1 < len) {
          i += 2
          continue
        }
        if (text[i] === '"') {
          i++
          closed = true
          break
        }
        i++
      }
      tokens.push({
        type: closed ? "string" : "unterminated_string",
        value: text.slice(start, i),
        start,
        end: i,
      })
      continue
    }

    const symbol = SYMBOLS.find((s) => text.startsWith(s, i))
    if (symbol) {
      i += symbol.length
      tokens.push({ type: "symbol", value: symbol, start, end: i })
      continue
    }

    if (IDENT_RE.test(ch)) {
      while (i < len && IDENT_RE.test(text[i])) i++
      tokens.push({ type: "ident", value: text.slice(start, i), start, end: i })
      continue
    }

    i++
    tokens.push({ type: "unknown", value: ch, start, end: i })
  }

  return tokens
}

// Walks the token stream left-to-right with a small state machine mirroring
// the grammar (term := NOT term | "(" orExpr ")" | COLUMN OP value), tagging
// each token with a semantic `role` for highlighting and capturing the
// automaton state *before* each token so we can compute suggestions for any
// caret position.
function nextNonWhitespace(tokens, start) {
  for (let i = start; i < tokens.length; i++) {
    if (tokens[i].type !== "whitespace") return i
  }
  return -1
}

// Two-word operators, keyed by their first word. In operator position the
// leading `not` of "not like" is part of the operator, not the NOT keyword.
const TWO_WORD_OPERATORS = { is: "is not", not: "not like" }

function classify(tokens) {
  let state = "term_start" // term_start | operator | value | connective
  let column = null
  let operator = null
  let parens = 0

  const entries = []
  let i = 0

  while (i < tokens.length) {
    const token = tokens[i]
    const before = { state, column, operator, parens }

    if (token.type === "whitespace") {
      entries.push({ token, before, role: "whitespace" })
      i++
      continue
    }

    const lower = token.value.toLowerCase()

    if (state === "term_start") {
      let role
      if (token.value === "(") {
        parens++
        role = "paren"
      } else if (lower === "not") {
        role = "keyword"
      } else {
        role = "column"
        column = lower
        state = "operator"
      }
      entries.push({ token, before, role })
      i++
    } else if (state === "operator") {
      // Recognize two-word operators ("is not", "not like"), marking both words
      // (and the whitespace between) as the operator.
      const nextIdx = nextNonWhitespace(tokens, i + 1)
      const next = nextIdx >= 0 ? tokens[nextIdx] : null
      const twoWord = TWO_WORD_OPERATORS[lower]

      if (
        twoWord &&
        next &&
        next.type === "ident" &&
        twoWord === `${lower} ${next.value.toLowerCase()}`
      ) {
        operator = twoWord
        entries.push({ token, before, role: "operator" })
        for (let j = i + 1; j < nextIdx; j++) {
          entries.push({ token: tokens[j], before, role: "whitespace" })
        }
        entries.push({ token: next, before, role: "operator" })
        i = nextIdx + 1
      } else {
        operator = lower
        entries.push({ token, before, role: "operator" })
        i++
      }
      state = "value"
    } else if (state === "value") {
      const role =
        token.type === "string" || token.type === "unterminated_string"
          ? "string"
          : "value"
      entries.push({ token, before, role })
      state = "connective"
      i++
    } else {
      let role
      if (token.value === ")") {
        parens = Math.max(0, parens - 1)
        role = "paren"
      } else if (lower === "and" || lower === "or") {
        role = "keyword"
        state = "term_start"
      } else {
        role = "error"
      }
      entries.push({ token, before, role })
      i++
    }
  }

  return { entries, final: { state, column, operator, parens } }
}

function contextAt(classified, caret) {
  for (const entry of classified.entries) {
    if (caret <= entry.token.end) {
      let prefix = ""
      let tokenStart = caret

      if (entry.role !== "whitespace") {
        prefix = entry.token.value.slice(0, caret - entry.token.start)
        if (
          entry.token.type === "string" ||
          entry.token.type === "unterminated_string"
        ) {
          prefix = prefix.replace(/^"/, "")
        }
        tokenStart = entry.token.start
      }

      return { ...entry.before, prefix, tokenStart }
    }
  }

  return { ...classified.final, prefix: "", tokenStart: caret }
}

// A suggestion candidate may be a plain string (label === value) or an object
// `{ label, value }` where the dropdown shows `label` but the query gets `value`
// (e.g. firmware shows "<version> - <short uuid>" but inserts the full UUID).
function normalizeCandidate(candidate) {
  return typeof candidate === "string"
    ? { label: candidate, value: candidate }
    : candidate
}

function suggestionsFor(ctx, schema) {
  const prefix = ctx.prefix.toLowerCase()
  let candidates = []

  if (ctx.state === "term_start") {
    candidates = schema.columns
  } else if (ctx.state === "operator") {
    candidates = schema.operators[ctx.column] || []
  } else if (ctx.state === "value") {
    candidates = schema.values[ctx.column] || []
  } else {
    candidates = ctx.parens > 0 ? ["and", "or", ")"] : ["and", "or"]
  }

  // Match against the displayed label.
  return candidates
    .map(normalizeCandidate)
    .filter(
      ({ label }) =>
        label.toLowerCase().startsWith(prefix) &&
        label.toLowerCase() !== prefix,
    )
}

const TOKEN_CLASSES = "rounded border px-1"

const ROLE_CLASSES = {
  column:
    "border-sky-500/40 bg-sky-500/10 text-sky-300 light:border-sky-300 light:bg-sky-100 light:text-sky-800",
  operator:
    "border-fuchsia-500/40 bg-fuchsia-500/10 text-fuchsia-300 light:border-fuchsia-300 light:bg-fuchsia-100 light:text-fuchsia-800",
  value:
    "border-amber-500/40 bg-amber-500/10 text-amber-300 light:border-amber-300 light:bg-amber-100 light:text-amber-800",
  string:
    "border-emerald-500/40 bg-emerald-500/10 text-emerald-300 light:border-emerald-300 light:bg-emerald-100 light:text-emerald-800",
  keyword:
    "border-indigo-500/40 bg-indigo-500/10 text-indigo-300 font-semibold light:border-indigo-300 light:bg-indigo-100 light:text-indigo-800 mx-1",
  paren: "border-base-600 bg-base-800 text-base-300",
  error:
    "border-red-500/50 bg-red-500/10 text-red-300 underline light:border-red-300 light:bg-red-100 light:text-red-800",
}

// `contenteditable` frequently inserts non-breaking spaces (U+00A0) when you
// type a normal space, especially around the styled token chips. JavaScript's
// `\s` treats them as whitespace so highlighting still works, but the Elixir
// lexer only accepts ASCII whitespace and rejects them - so normalize back to
// regular spaces both for display and before submitting the query.
function normalizeSpaces(s) {
  return s.replace(/\u00A0/g, " ")
}

// A trailing "tail" element is appended after the rightmost token chip to act as
// a dedicated editable landing spot for the caret outside the tokens (entered via
// Right arrow / Escape). It holds a zero-width space (U+200B) so the caret has a
// real text position, and is excluded from the query value.
const TAIL_SENTINEL = "\u200B"
const TAIL_CLASS = "pl-1"
const TAIL_HTML = `<span data-role="tail" class="${TAIL_CLASS}">${TAIL_SENTINEL}</span>`

// The editable value, with the tail sentinel and non-breaking spaces removed.
function cleanValue(s) {
  return normalizeSpaces(s).replace(/\u200B/g, "")
}

function escapeHtml(s) {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

function renderHtml(entries) {
  return entries
    .map(({ token, role }) => {
      if (role === "whitespace" || !ROLE_CLASSES[role])
        return escapeHtml(normalizeSpaces(token.value))
      return `<span class="${TOKEN_CLASSES} ${ROLE_CLASSES[role]}">${escapeHtml(token.value)}</span>`
    })
    .join("")
}

// Caret position measured in *value* characters - i.e. ignoring the tail
// sentinel - so it lines up with the tokenized value.
function caretOffset(el) {
  const selection = window.getSelection()
  if (!selection || !selection.rangeCount)
    return cleanValue(el.textContent).length

  const range = selection.getRangeAt(0)
  const preRange = range.cloneRange()
  preRange.selectNodeContents(el)
  preRange.setEnd(range.endContainer, range.endOffset)
  return cleanValue(preRange.toString()).length
}

function tailEl(el) {
  return el.querySelector('[data-role="tail"]')
}

// Places the caret at the given value offset within the token region, never the
// tail (the tail is only entered explicitly, via Right arrow / Escape). The
// caret rests inside the relevant token chip's text, which keeps it visible
// while a token is being typed.
function setCaretOffset(el, offset) {
  const range = document.createRange()
  const selection = window.getSelection()
  if (!selection) return

  const tail = tailEl(el)
  let remaining = offset
  let placement = null

  const walk = (parent) => {
    for (const child of parent.childNodes) {
      if (placement) return
      if (child === tail) continue
      if (child.nodeType === Node.TEXT_NODE) {
        const len = child.textContent.length
        if (remaining <= len) {
          placement = { node: child, offset: remaining }
          return
        }
        remaining -= len
      } else {
        walk(child)
      }
    }
  }

  walk(el)

  if (placement) {
    range.setStart(placement.node, placement.offset)
  } else {
    // Past the end of the value: collapse to the end of the token region,
    // before the tail.
    range.selectNodeContents(el)
    if (tail) range.setEndBefore(tail)
    range.collapse(false)
    selection.removeAllRanges()
    selection.addRange(range)
    return
  }

  range.collapse(true)
  selection.removeAllRanges()
  selection.addRange(range)
}

const COLLAPSED_WIDTH = "w-64"
const EXPANDED_WIDTH = "w-136"
const COLLAPSE_DELAY = 120

export default {
  mounted() {
    this.loadSchema()

    this.wrapper = this.el
    this.box = this.el.querySelector('[data-role="box"]')
    this.hints = this.el.querySelector('[data-role="hints"]')
    this.searchIcon = this.el.querySelector('[data-role="search-icon"]')
    this.clearButton = this.el.querySelector('[data-role="clear"]')
    this.placeholder = this.el.querySelector('[data-role="placeholder"]')
    this.editor = this.el.querySelector('[data-role="editor"]')
    this.suggestionsEl = this.el.querySelector('[data-role="suggestions"]')

    this.activeSuggestions = []
    this.activeIndex = -1

    this.editor.textContent = this.el.dataset.value || ""
    this.highlight()
    this.updateClearButtonVisibility()
    this.applyRestingWidth({ animate: false })

    this.editor.addEventListener("input", () => this.handleInput())
    this.editor.addEventListener("keydown", (event) =>
      this.handleKeydown(event),
    )
    // Bound to both "focus" (e.g. Tab) and "click" - a click on an already-focused
    // editor won't refire "focus", and some environments don't reliably cascade a
    // synthetic click into a native focus event, so cover both explicitly.
    this.editor.addEventListener("click", () => this.expand())
    this.editor.addEventListener("focus", () => this.expand())
    this.editor.addEventListener("blur", () => this.scheduleCollapse())

    this.editor.addEventListener("paste", (event) => {
      event.preventDefault()
      const text = event.clipboardData.getData("text/plain")
      document.execCommand("insertText", false, text)
    })

    this.clearButton.addEventListener("mousedown", (event) => {
      event.preventDefault()
      this.editor.textContent = ""
      this.highlight()
      this.updateClearButtonVisibility()
      this.pushEvent("clear-advanced-query", {})
    })

    window.addEventListener("keydown", (event) => {
      if (event.key === "/") {
        event.preventDefault()
        this.editor.focus()
        this.expand()
      }
    })
  },

  // The schema (column/operator/value whitelist) is loaded asynchronously
  // server-side, so `data-schema` may still be the empty placeholder on the
  // first `mounted()` call - re-read it on every update so it picks up the
  // real values once they arrive, without touching the editor's contents.
  updated() {
    this.loadSchema()

    // Keep the resting width in sync when the server patches the field (e.g.
    // a query is applied or cleared) while it isn't being actively edited.
    if (document.activeElement !== this.editor) {
      this.applyRestingWidth()
    }
  },

  loadSchema() {
    this.schema = JSON.parse(this.el.dataset.schema || "{}")
    this.schema.operators = this.schema.operators || {}
    this.schema.values = this.schema.values || {}
    this.schema.columns = this.schema.columns || []
  },

  hasQuery() {
    return this.value().trim() !== ""
  },

  // The field rests at the collapsed width when empty, but stays expanded once
  // a query has been entered so an applied query remains readable without focus.
  // Pass `animate: false` to set the width without running the width transition
  // (used on initial mount to avoid animating on page load).
  applyRestingWidth({ animate = true } = {}) {
    if (!animate) this.wrapper.classList.remove("transition-[width]")

    if (this.hasQuery()) {
      this.wrapper.classList.remove(COLLAPSED_WIDTH)
      this.wrapper.classList.add(EXPANDED_WIDTH)
    } else {
      this.wrapper.classList.add(COLLAPSED_WIDTH)
      this.wrapper.classList.remove(EXPANDED_WIDTH)
    }

    if (!animate) {
      // Force a reflow so the width change applies before the transition is
      // restored, otherwise re-adding the class would animate it.
      void this.wrapper.offsetWidth
      this.wrapper.classList.add("transition-[width]")
    }
  },

  expand() {
    clearTimeout(this.collapseTimer)

    this.wrapper.classList.remove(COLLAPSED_WIDTH)
    this.wrapper.classList.add(EXPANDED_WIDTH)
    this.hints.classList.remove("hidden")
    this.placeholder.classList.add("hidden")

    this.updateSuggestions()
  },

  scheduleCollapse() {
    // Suggestion/clear clicks use mousedown+preventDefault so focus never
    // leaves the editor, but this is a small safety net against focus-shift
    // timing quirks across browsers.
    if (this.value() == "") {
      this.placeholder.classList.remove("hidden")
    }
    this.collapseTimer = setTimeout(() => this.collapse(), COLLAPSE_DELAY)
  },

  collapse() {
    // Keep the field expanded while a query is present; only shrink when empty.
    this.applyRestingWidth()

    this.hideSuggestions()
  },

  updateClearButtonVisibility() {
    const empty = this.value() === ""
    this.clearButton.classList.toggle("hidden", empty)
    this.searchIcon.classList.toggle("hidden", !empty)
  },

  // The query value, excluding the tail sentinel.
  value() {
    return cleanValue(this.editor.textContent)
  },

  handleInput() {
    this.highlight()
    this.updateSuggestions()
    this.updateClearButtonVisibility()
  },

  // Rebuilds the chip markup for `value` and appends the trailing tail element
  // (when there's at least one token, so the empty-state placeholder still works).
  render(value) {
    const classified = classify(tokenize(value))
    const hasTokens = classified.entries.some((e) => e.role !== "whitespace")

    this.editor.innerHTML =
      renderHtml(classified.entries) + (hasTokens ? TAIL_HTML : "")
    this.classified = classified
  },

  highlight() {
    const value = this.value()
    const offset = caretOffset(this.editor)

    this.render(value)
    setCaretOffset(this.editor, offset)
  },

  // Moves the caret into the trailing tail element so it sits in an editable
  // area to the right of the rightmost token. When `separate` is set (a
  // deliberate token exit, e.g. Right arrow) a trailing space is added first so
  // the next thing typed starts a new token; on a plain dismiss (Escape) the
  // value is left untouched.
  exitToTail({ separate = true } = {}) {
    const value = this.value()
    const separated =
      separate && value.length > 0 && !/\s$/.test(value) ? value + " " : value

    this.render(separated)
    this.editor.focus()

    const tail = tailEl(this.editor)
    if (tail && tail.firstChild) {
      const range = document.createRange()
      range.setStart(tail.firstChild, tail.firstChild.length)
      range.collapse(true)
      const selection = window.getSelection()
      selection.removeAllRanges()
      selection.addRange(range)
    } else {
      setCaretOffset(this.editor, separated.length)
    }

    this.updateSuggestions()
    this.updateClearButtonVisibility()
  },

  caretInTail() {
    const tail = tailEl(this.editor)
    const selection = window.getSelection()
    return !!(
      tail &&
      selection.anchorNode &&
      tail.contains(selection.anchorNode)
    )
  },

  updateSuggestions() {
    const offset = caretOffset(this.editor)
    const classified = this.classified || classify(tokenize(this.value()))
    const ctx = contextAt(classified, offset)
    const suggestions = suggestionsFor(ctx, this.schema)

    this.currentCtx = ctx
    this.activeSuggestions = suggestions
    this.activeIndex = -1

    this.renderSuggestions()
  },

  renderSuggestions() {
    if (this.activeSuggestions.length === 0) {
      this.suggestionsEl.innerHTML = ""
      return
    }

    this.suggestionsEl.innerHTML = `
      <div class="bg-surface-muted border-base-700 absolute left-0 right-0 z-40 mt-1 max-h-48 overflow-auto rounded border shadow-lg">
        ${this.activeSuggestions
          .map(
            (suggestion, index) => `
              <button
                type="button"
                data-index="${index}"
                class="block w-full px-3 py-1.5 text-left text-sm font-mono ${index === this.activeIndex ? "bg-base-800 text-base-50" : "text-base-300"}"
              >${escapeHtml(suggestion.label)}</button>
            `,
          )
          .join("")}
      </div>
    `

    this.suggestionsEl.querySelectorAll("button").forEach((button) => {
      button.addEventListener("mousedown", (event) => {
        event.preventDefault()
        this.acceptSuggestion(
          this.activeSuggestions[Number(button.dataset.index)],
        )
      })
    })

    // Keep the highlighted item visible when navigating with the arrow keys.
    if (this.activeIndex >= 0) {
      const active = this.suggestionsEl.querySelector(
        `button[data-index="${this.activeIndex}"]`,
      )
      if (active) active.scrollIntoView({ block: "nearest" })
    }
  },

  hideSuggestions() {
    this.activeSuggestions = []
    this.activeIndex = -1
    this.suggestionsEl.innerHTML = ""
    this.hints.classList.add("hidden")
  },

  acceptSuggestion(suggestion) {
    if (!this.currentCtx) return

    const value = this.value()
    const { tokenStart, state } = this.currentCtx
    const caret = caretOffset(this.editor)
    const replacement =
      state === "value" ? `"${suggestion.value}"` : suggestion.value
    const insertion = `${replacement} `

    const newValue = value.slice(0, tokenStart) + insertion + value.slice(caret)
    const newCaret = tokenStart + insertion.length

    this.render(newValue)
    setCaretOffset(this.editor, newCaret)
    this.updateSuggestions()
    this.updateClearButtonVisibility()
  },

  handleKeydown(event) {
    if (event.key === "ArrowDown" && this.activeSuggestions.length > 0) {
      event.preventDefault()
      this.activeIndex = (this.activeIndex + 1) % this.activeSuggestions.length
      this.renderSuggestions()
      return
    }

    if (event.key === "ArrowUp" && this.activeSuggestions.length > 0) {
      event.preventDefault()
      this.activeIndex =
        (this.activeIndex - 1 + this.activeSuggestions.length) %
        this.activeSuggestions.length
      this.renderSuggestions()
      return
    }

    if (event.key === "ArrowRight") {
      // At the end of the rightmost token, Right arrow exits the token into the
      // trailing tail element rather than staying glued to the chip.
      const value = this.value()
      if (
        !this.caretInTail() &&
        value.length > 0 &&
        caretOffset(this.editor) >= value.length
      ) {
        event.preventDefault()
        this.exitToTail()
      }
      return
    }

    if (event.key === "Escape") {
      // First Escape dismisses the open suggestion list but keeps focus in the
      // field; a second Escape (nothing left to dismiss) exits the field.
      if (this.activeSuggestions.length > 0) {
        event.preventDefault()

        if (this.hints.classList.contains("hidden")) {
          this.editor.blur()
        } else {
          this.collapse()

          // Browsers stop rendering the caret after Escape in a contenteditable
          // even though focus/selection are retained, making it look like the
          // field was exited. Move the caret into the trailing tail element so it
          // stays visible, outside the rightmost token, without altering the query.
          this.exitToTail({ separate: false })
        }
      } else {
        this.editor.blur()
      }
      return
    }

    if (event.key === "Enter" || event.key === "Tab") {
      event.preventDefault()

      if (
        !this.hints.classList.contains("hidden") &&
        this.activeSuggestions.length > 0 &&
        this.activeIndex >= 0
      ) {
        this.acceptSuggestion(this.activeSuggestions[this.activeIndex])
      } else if (event.key === "Enter") {
        this.apply()
      }
    }
  },

  apply() {
    this.hideSuggestions()
    this.editor.blur()
    this.pushEvent("apply-advanced-query", { query: this.value().trimEnd() })
  },
}
