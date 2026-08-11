// Unit tests for the pure keyboard-decision helpers in commandPalette.js.
// Runs on Node's built-in test runner - no dependencies, no DOM:
//
//   node --test assets/js
//
// The DOM half of the hook (showing the overlay, focus, click-through) needs a
// real browser to test meaningfully and is not covered here.
import { describe, it } from "node:test"
import assert from "node:assert/strict"

import { isToggleShortcut, navAction } from "./commandPalette.js"

describe("isToggleShortcut", () => {
  it("is true for Cmd+K", () => {
    assert.equal(isToggleShortcut({ metaKey: true, ctrlKey: false, key: "k" }), true)
  })

  it("is true for Ctrl+K", () => {
    assert.equal(isToggleShortcut({ metaKey: false, ctrlKey: true, key: "k" }), true)
  })

  it("is case-insensitive on the key", () => {
    assert.equal(isToggleShortcut({ metaKey: true, ctrlKey: false, key: "K" }), true)
  })

  it("is false without a modifier", () => {
    assert.equal(isToggleShortcut({ metaKey: false, ctrlKey: false, key: "k" }), false)
  })

  it("is false for a different key with a modifier", () => {
    assert.equal(isToggleShortcut({ metaKey: true, ctrlKey: false, key: "j" }), false)
  })
})

describe("navAction", () => {
  it("does nothing when there are no results", () => {
    assert.deepEqual(navAction("ArrowDown", { activeIndex: -1, count: 0 }), {
      type: "none",
    })
  })

  it("moves to the first item on ArrowDown from nothing highlighted", () => {
    assert.deepEqual(navAction("ArrowDown", { activeIndex: -1, count: 3 }), {
      type: "move",
      index: 0,
    })
  })

  it("wraps to the top after the last item", () => {
    assert.deepEqual(navAction("ArrowDown", { activeIndex: 2, count: 3 }), {
      type: "move",
      index: 0,
    })
  })

  it("wraps to the bottom on ArrowUp from the top", () => {
    assert.deepEqual(navAction("ArrowUp", { activeIndex: 0, count: 3 }), {
      type: "move",
      index: 2,
    })
  })

  it("wraps to the bottom on ArrowUp from nothing highlighted", () => {
    assert.deepEqual(navAction("ArrowUp", { activeIndex: -1, count: 3 }), {
      type: "move",
      index: 2,
    })
  })

  it("selects the highlighted item on Enter", () => {
    assert.deepEqual(navAction("Enter", { activeIndex: 1, count: 3 }), {
      type: "select",
      index: 1,
    })
  })

  it("selects the first item on Enter when nothing is highlighted", () => {
    assert.deepEqual(navAction("Enter", { activeIndex: -1, count: 3 }), {
      type: "select",
      index: 0,
    })
  })

  it("ignores other keys", () => {
    assert.deepEqual(navAction("a", { activeIndex: 0, count: 3 }), { type: "none" })
  })
})
