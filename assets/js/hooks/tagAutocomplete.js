// Adds an autocomplete dropdown to a tags text input.
//
// The wrapper element carries `data-available-tags` (a JSON array of known
// tags) and contains:
//   - an `<input data-tag-input>` holding the value
//   - a `<ul data-tag-suggestions>` the hook populates with matches
//
// By default the input holds a comma-separated list of tags and the token
// after the last comma is the one being matched/completed. Add `data-single`
// to the wrapper for inputs that hold a single tag (e.g. the per-device "add
// tag" field): the whole value is treated as one token and selecting a
// suggestion replaces it outright with no trailing separator.
//
// Matching is case-insensitive and excludes tags already committed in the
// input. Selecting a suggestion dispatches an `input` event so LiveView's
// phx-change validation picks up the new value.
export default {
  mounted() {
    this.input = this.el.querySelector("[data-tag-input]")
    this.list = this.el.querySelector("[data-tag-suggestions]")
    this.single = this.el.hasAttribute("data-single")

    try {
      this.available = JSON.parse(this.el.dataset.availableTags || "[]")
    } catch {
      this.available = []
    }

    this.activeIndex = -1

    this.onInput = () => this.renderSuggestions()
    this.onFocus = () => this.renderSuggestions()
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
    try {
      this.available = JSON.parse(this.el.dataset.availableTags || "[]")
    } catch {
      this.available = []
    }
  },

  destroyed() {
    this.input.removeEventListener("input", this.onInput)
    this.input.removeEventListener("focus", this.onFocus)
    this.input.removeEventListener("keydown", this.onKeydown)
    this.input.removeEventListener("blur", this.onBlur)
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

  matches() {
    const token = this.currentToken().toLowerCase()
    const taken = new Set(this.existingTokens().map((t) => t.toLowerCase()))

    return this.available.filter((tag) => {
      const lower = tag.toLowerCase()
      if (taken.has(lower)) return false
      // An empty token (e.g. right after a comma) offers all unused tags.
      return token === "" || lower.includes(token)
    })
  },

  renderSuggestions() {
    const matches = this.matches()

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
