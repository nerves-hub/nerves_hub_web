// Unit tests for the TagAutocomplete hook's commit mode (`data-commit-event`),
// where Enter or a comma adds the typed tag instead of leaving it in the field.
// Runs on Node's built-in test runner, so the hook's methods are called on a
// stand-in for the element rather than on a real DOM.
import { describe, it } from "node:test"
import assert from "node:assert/strict"

import TagAutocomplete from "./tagAutocomplete.js"

function hook({ value = "", listHidden = true, activeIndex = -1 } = {}) {
  const pushed = []

  const instance = Object.assign(Object.create(TagAutocomplete), {
    commitEvent: "add-tag",
    single: true,
    input: { value, focus() {} },
    list: { hidden: listHidden, innerHTML: "" },
    activeIndex,
    pushEvent: (event, payload) => pushed.push([event, payload]),
  })

  return { instance, pushed }
}

function keydown(key) {
  return {
    key,
    defaultPrevented: false,
    preventDefault() {
      this.defaultPrevented = true
    },
  }
}

describe("commit mode", () => {
  it("adds the typed tag on Enter, without submitting the form", () => {
    const { instance, pushed } = hook({ value: " roof-2 " })
    const event = keydown("Enter")

    assert.equal(instance.commitKey(event), true)
    assert.equal(event.defaultPrevented, true)
    assert.deepEqual(pushed, [["add-tag", { tag: "roof-2" }]])
    assert.equal(instance.input.value, "")
  })

  it("adds the typed tag on a comma, and doesn't type the comma", () => {
    const { instance, pushed } = hook({ value: "roof-2" })
    const event = keydown(",")

    assert.equal(instance.commitKey(event), true)
    assert.equal(event.defaultPrevented, true)
    assert.deepEqual(pushed, [["add-tag", { tag: "roof-2" }]])
  })

  it("leaves Enter to submit the form when nothing is typed", () => {
    const { instance, pushed } = hook({ value: "  " })
    const event = keydown("Enter")

    assert.equal(instance.commitKey(event), false)
    assert.equal(event.defaultPrevented, false)
    assert.deepEqual(pushed, [])
  })

  it("swallows a comma when nothing is typed", () => {
    const { instance, pushed } = hook()
    const event = keydown(",")

    assert.equal(instance.commitKey(event), true)
    assert.equal(event.defaultPrevented, true)
    assert.deepEqual(pushed, [])
  })

  it("leaves Enter to the highlighted suggestion", () => {
    const { instance, pushed } = hook({ value: "ro", listHidden: false, activeIndex: 0 })

    assert.equal(instance.commitKey(keydown("Enter")), false)
    assert.deepEqual(pushed, [])
  })

  it("ignores other keys", () => {
    const { instance, pushed } = hook({ value: "roof" })

    assert.equal(instance.commitKey(keydown("a")), false)
    assert.deepEqual(pushed, [])
  })

  it("adds a picked suggestion straight away", () => {
    const { instance, pushed } = hook({ value: "ro", listHidden: false })

    instance.select("roof-2")

    assert.deepEqual(pushed, [["add-tag", { tag: "roof-2" }]])
    assert.equal(instance.input.value, "")
  })
})
