// Adds an autocomplete dropdown to a tags text input.
//
// The wrapper element contains:
//   - an `<input data-tag-input>` holding the value
//   - a `<ul data-tag-suggestions>` the hook populates with matches
//
// Suggestions come from one of two places:
//
//   - `data-available-tags` — a JSON array of every known tag, matched in the
//     browser. Fine for the small sets (a product's script tags, say).
//   - `data-tag-search="<event>"` — the name of a LiveView event the hook pushes
//     the token to, which replies with the matches. For device tags, where the
//     biggest products have thousands: sending them all is hundreds of kilobytes
//     of markup and a dropdown nobody can read. Nothing is suggested until
//     something is typed, since a list of arbitrary tags helps no one.
//
// By default the input holds a comma-separated list of tags and the token
// after the last comma is the one being matched/completed. Add `data-single`
// to the wrapper for inputs that hold a single tag (e.g. the per-device "add
// tag" field): the whole value is treated as one token and selecting a
// suggestion replaces it outright with no trailing separator.
//
// Matching excludes tags already committed in the input. Selecting a suggestion
// dispatches an `input` event so LiveView's phx-change validation picks up the
// new value.

// Long enough that typing a word is one request rather than one per letter,
// short enough to feel like it is keeping up.
const SEARCH_DEBOUNCE_MS = 150

export default {
  mounted() {
    this.input = this.el.querySelector("[data-tag-input]")
    this.list = this.el.querySelector("[data-tag-suggestions]")
    this.single = this.el.hasAttribute("data-single")
    this.searchEvent = this.el.dataset.tagSearch || null

    this.readAvailable()

    this.activeIndex = -1
    this.searchTimer = null
    // Replies can arrive out of order; only the newest token's matches are shown.
    this.pendingToken = null

    this.onInput = () => this.suggest()
    this.onFocus = () => this.suggest()
    this.onKeydown = (event) => this.handleKeydown(event)
    // Delay hiding so a mousedown on a suggestion can register first.
    this.onBlur = () => setTimeout(() => this.hide(), 150)

    this.input.addEventListener("input", this.onInput)
    this.input.addEventListener("focus", this.onFocus)
    this.input.addEventListener("keydown", this.onKeydown)
    this.input.addEventListener("blur", this.onBlur)
  },

  updated() {
    // Available tags may change after a server round-trip.
    this.readAvailable()
  },

  destroyed() {
    clearTimeout(this.searchTimer)
    this.input.removeEventListener("input", this.onInput)
    this.input.removeEventListener("focus", this.onFocus)
    this.input.removeEventListener("keydown", this.onKeydown)
    this.input.removeEventListener("blur", this.onBlur)
  },

  readAvailable() {
    try {
      this.available = JSON.parse(this.el.dataset.availableTags || "[]")
    } catch {
      this.available = []
    }
  },

  // The tokens already committed before the one being typed. The final part
  // is the in-progress token, so it is excluded — otherwise typing a tag in
  // full would filter that tag out of its own suggestions. Single inputs hold
  // just the in-progress token, so nothing is committed yet.
  existingTokens() {
    if (this.single) return []

    return this.input.value
      .split(",")
      .slice(0, -1)
      .map((t) => t.trim())
      .filter((t) => t.length > 0)
  },

  currentToken() {
    if (this.single) return this.input.value.trim()

    const parts = this.input.value.split(",")
    return parts[parts.length - 1].trim()
  },

  suggest() {
    if (this.searchEvent) {
      this.searchOnServer()
    } else {
      this.render(this.matches())
    }
  },

  // Debounced, so holding down a key is not one query per character.
  searchOnServer() {
    const token = this.currentToken()

    clearTimeout(this.searchTimer)

    if (token === "") {
      this.hide()
      return
    }

    this.searchTimer = setTimeout(() => {
      this.pendingToken = token

      this.pushEvent(this.searchEvent, { query: token }, (reply) => {
        // A slower reply for an earlier token would otherwise overwrite the
        // matches for what is in the field now.
        if (this.pendingToken !== token) return

        this.render(this.withoutTaken(reply?.tags || []))
      })
    }, SEARCH_DEBOUNCE_MS)
  },

  matches() {
    const token = this.currentToken().toLowerCase()

    return this.withoutTaken(
      this.available.filter((tag) => {
        // An empty token (e.g. right after a comma) offers all unused tags.
        return token === "" || tag.toLowerCase().includes(token)
      })
    )
  },

  // A tag already in the input is not worth offering again. Case-insensitive,
  // since tags differing only in case are the same tag to a person.
  withoutTaken(tags) {
    const taken = new Set(this.existingTokens().map((t) => t.toLowerCase()))

    return tags.filter((tag) => !taken.has(tag.toLowerCase()))
  },

  render(matches) {
    if (matches.length === 0) {
      this.hide()
      return
    }

    this.activeIndex = -1
    this.list.innerHTML = ""

    matches.forEach((tag) => {
      const li = document.createElement("li")
      li.textContent = tag
      li.setAttribute("role", "option")
      li.dataset.tag = tag
      li.className =
        "cursor-pointer px-2 py-1.5 text-sm text-base-300 hover:bg-base-800"
      // Use mousedown so the selection happens before the input's blur.
      li.addEventListener("mousedown", (event) => {
        event.preventDefault()
        this.select(tag)
      })
      this.list.appendChild(li)
    })

    this.list.hidden = false
  },

  hide() {
    this.list.hidden = true
    this.list.innerHTML = ""
    this.activeIndex = -1
  },

  handleKeydown(event) {
    if (this.list.hidden) return

    const options = Array.from(this.list.children)
    if (options.length === 0) return

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        this.activeIndex = (this.activeIndex + 1) % options.length
        this.highlight(options)
        break
      case "ArrowUp":
        event.preventDefault()
        this.activeIndex =
          (this.activeIndex - 1 + options.length) % options.length
        this.highlight(options)
        break
      case "Enter":
        if (this.activeIndex >= 0) {
          event.preventDefault()
          this.select(options[this.activeIndex].dataset.tag)
        }
        break
      case "Escape":
        this.hide()
        break
    }
  },

  highlight(options) {
    options.forEach((option, index) => {
      option.classList.toggle("bg-base-800", index === this.activeIndex)
    })
    if (this.activeIndex >= 0) {
      options[this.activeIndex].scrollIntoView({ block: "nearest" })
    }
  },

  select(tag) {
    if (this.single) {
      // Single-tag inputs hold exactly one tag, no trailing separator.
      this.input.value = tag
    } else {
      const parts = this.input.value.split(",")
      parts[parts.length - 1] = ` ${tag}`

      // Rebuild the value and leave a trailing separator ready for the next tag.
      const value = parts
        .map((t) => t.trim())
        .filter((t) => t.length > 0)
        .join(", ")

      this.input.value = `${value}, `
    }

    this.hide()
    this.input.focus()
    this.input.dispatchEvent(new Event("input", { bubbles: true }))
  },
}
