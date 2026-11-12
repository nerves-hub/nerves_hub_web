// Unit tests for what the terminal's phone key bar sends.
// Runs on Node's built-in test runner - no dependencies, no DOM:
//
//   node --test assets/js
import { describe, it } from "node:test"
import assert from "node:assert/strict"

import { keySequence, withControl } from "./terminalKeyboard.js"

describe("keySequence", () => {
  it("sends Esc and Tab as their characters", () => {
    assert.equal(keySequence("esc"), "\x1b")
    assert.equal(keySequence("tab"), "\t")
  })

  it("sends arrows in normal cursor key mode", () => {
    assert.equal(keySequence("up"), "\x1b[A")
    assert.equal(keySequence("down"), "\x1b[B")
    assert.equal(keySequence("right"), "\x1b[C")
    assert.equal(keySequence("left"), "\x1b[D")
  })

  it("sends arrows in application cursor key mode", () => {
    assert.equal(keySequence("up", true), "\x1bOA")
    assert.equal(keySequence("left", true), "\x1bOD")
  })

  it("sends nothing for a key it doesn't know", () => {
    assert.equal(keySequence("ctrl"), null)
  })
})

describe("withControl", () => {
  it("turns a letter into its control code, either case", () => {
    assert.equal(withControl("c"), "\x03")
    assert.equal(withControl("C"), "\x03")
    assert.equal(withControl("d"), "\x04")
  })

  it("covers the punctuation with control codes", () => {
    assert.equal(withControl("["), "\x1b")
    assert.equal(withControl("@"), "\x00")
    assert.equal(withControl("?"), "\x7f")
  })

  it("leaves anything else alone", () => {
    assert.equal(withControl("1"), "1")
    assert.equal(withControl(" "), " ")
    assert.equal(withControl("ab"), "ab")
  })
})
