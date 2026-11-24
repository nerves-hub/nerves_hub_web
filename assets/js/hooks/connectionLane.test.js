// Unit tests for the connection lane's selection and the charts' matching.
// Runs on Node's built-in test runner - no dependencies, no DOM:
//
//   node --test assets/js
import { describe, it } from "node:test"
import assert from "node:assert/strict"

import { highlightedKey, overlaps, toggle } from "./connectionLane.js"

describe("highlightedKey", () => {
  it("prefers what's under the pointer to what's selected", () => {
    assert.equal(highlightedKey("2", "1"), "2")
  })

  it("falls back to what's selected, then to nothing", () => {
    assert.equal(highlightedKey(null, "1"), "1")
    assert.equal(highlightedKey(null, null), null)
  })
})

describe("toggle", () => {
  it("selects a span, moves to another, and clears on a second tap", () => {
    assert.equal(toggle(null, "1"), "1")
    assert.equal(toggle("1", "2"), "2")
    assert.equal(toggle("2", "2"), null)
  })
})

describe("overlaps", () => {
  it("matches a band cut to a different range", () => {
    assert.equal(overlaps([100, 200], [150, 300]), true)
    assert.equal(overlaps([100, 200], [0, 120]), true)
  })

  it("doesn't match bands that only touch or lie apart", () => {
    assert.equal(overlaps([100, 200], [200, 300]), false)
    assert.equal(overlaps([100, 200], [300, 400]), false)
  })
})
