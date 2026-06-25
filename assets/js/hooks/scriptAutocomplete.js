// A searchable single-select combobox for picking a support script.
//
// Used in place of a native <select> when a product has many support
// scripts, so the list can be filtered by typing. The wrapper element
// carries:
//   - `data-scripts`: a JSON array of `{ id, name }` objects
//   - `data-selected-id`: the id of the currently selected script
// and contains:
//   - an `<input data-script-search>` the user types into
//   - a `<ul data-script-suggestions>` the hook populates with matches
//
// Matching is case-insensitive on the script name. Selecting a suggestion
// pushes a `select-script` event (with the script id as a string, matching
// the native <select> path) so the LiveView updates which script will run.
export default {
  mounted() {
    this.input = this.el.querySelector("[data-script-search]")
    this.list = this.el.querySelector("[data-script-suggestions]")

    this.loadScripts()
    this.activeIndex = -1

    this.onInput = () => this.renderSuggestions()
    this.onFocus = () => this.renderSuggestions()
    this.onKeydown = (event) => this.handleKeydown(event)
    // Delay so a mousedown on a suggestion registers before we reset/hide.
    this.onBlur = () => setTimeout(() => this.commitOrReset(), 150)

    this.input.addEventListener("input", this.onInput)
    this.input.addEventListener("focus", this.onFocus)
    this.input.addEventListener("keydown", this.onKeydown)
    this.input.addEventListener("blur", this.onBlur)
  },

  updated() {
    // Scripts or the selection may change after a server round-trip.
    this.loadScripts()
    // Don't clobber what the user is actively typing.
    if (document.activeElement !== this.input) {
      this.input.value = this.selectedName()
    }
  },

  destroyed() {
    this.input.removeEventListener("input", this.onInput)
    this.input.removeEventListener("focus", this.onFocus)
    this.input.removeEventListener("keydown", this.onKeydown)
    this.input.removeEventListener("blur", this.onBlur)
  },

  loadScripts() {
    try {
      this.scripts = JSON.parse(this.el.dataset.scripts || "[]")
    } catch {
      this.scripts = []
    }
  },

  selectedName() {
    const id = String(this.el.dataset.selectedId)
    const script = this.scripts.find((s) => String(s.id) === id)
    return script ? script.name : ""
  },

  matches() {
    const token = this.input.value.trim().toLowerCase()
    return this.scripts.filter(
      (script) => token === "" || script.name.toLowerCase().includes(token)
    )
  },

  renderSuggestions() {
    const matches = this.matches()

    if (matches.length === 0) {
      this.hide()
      return
    }

    this.activeIndex = -1
    this.list.innerHTML = ""

    matches.forEach((script) => {
      const li = document.createElement("li")
      li.textContent = script.name
      li.setAttribute("role", "option")
      li.dataset.id = script.id
      li.className =
        "cursor-pointer px-2 py-1.5 text-sm text-base-300 hover:bg-base-800"
      // Use mousedown so the selection happens before the input's blur.
      li.addEventListener("mousedown", (event) => {
        event.preventDefault()
        this.select(script)
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
      case "Enter": {
        event.preventDefault()
        const index = this.activeIndex >= 0 ? this.activeIndex : 0
        const id = options[index].dataset.id
        this.select(this.scripts.find((s) => String(s.id) === String(id)))
        break
      }
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

  select(script) {
    if (!script) return

    this.el.dataset.selectedId = script.id
    this.input.value = script.name
    this.hide()
    // Send the id as a string to match the native <select> change path.
    this.pushEvent("select-script", { script_id: String(script.id) })
  },

  // On blur, snap the text back to the selected script's name so the input
  // never shows a partial or unmatched search string.
  commitOrReset() {
    this.hide()
    this.input.value = this.selectedName()
  },
}
