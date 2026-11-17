// Unit tests for the key handling of devicePeek.js. Runs on Node's built-in
// test runner:
//
//   node --test assets/js
import { describe, it } from "node:test"
import assert from "node:assert/strict"

import { peekKeyAction } from "./devicePeek.js"

// A stand-in for an element: `closest` matches when the element is one of
// the kinds named.
const element = (...kinds) => ({
  closest: (selector) => (kinds.some((kind) => selector.includes(kind)) ? {} : null),
})

const key = (name, overrides = {}) => ({ key: name, target: element(), ...overrides })

describe("peekKeyAction", () => {
  it("moves down and up the list with the arrow keys", () => {
    assert.deepEqual(peekKeyAction(key("ArrowDown")), { type: "move", by: 1 })
    assert.deepEqual(peekKeyAction(key("ArrowUp")), { type: "move", by: -1 })
  })

  it("closes on escape and opens on enter", () => {
    assert.deepEqual(peekKeyAction(key("Escape")), { type: "close" })
    assert.deepEqual(peekKeyAction(key("Enter")), { type: "open" })
  })

  it("leaves every key to an open bulk popover", () => {
    for (const name of ["Escape", "ArrowDown", "Enter"]) {
      assert.equal(peekKeyAction(key(name), { popoverOpen: true }), null)
    }
  })

  it("leaves keys typed into a field alone", () => {
    for (const kind of ["input", "textarea", "contenteditable"]) {
      assert.equal(peekKeyAction(key("ArrowDown", { target: element(kind) })), null)
      assert.equal(peekKeyAction(key("Escape", { target: element(kind) })), null)
    }
  })

  it("leaves enter to a focused link or button", () => {
    assert.equal(peekKeyAction(key("Enter", { target: element("a[href]") })), null)
    assert.equal(peekKeyAction(key("Enter", { target: element("button") })), null)
    assert.deepEqual(peekKeyAction(key("ArrowDown", { target: element("button") })), { type: "move", by: 1 })
  })

  it("leaves keys with a modifier to other shortcuts", () => {
    for (const modifier of ["metaKey", "ctrlKey", "altKey", "shiftKey"]) {
      assert.equal(peekKeyAction(key("ArrowDown", { [modifier]: true })), null)
    }
  })

  it("ignores a key something else has handled", () => {
    assert.equal(peekKeyAction(key("Escape", { defaultPrevented: true })), null)
  })

  it("ignores other keys", () => {
    assert.equal(peekKeyAction(key("j")), null)
  })
})
