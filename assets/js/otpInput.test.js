// Unit tests for how otpInput.js cleans up what is typed or pasted into a
// one-time code field. Runs on Node's built-in test runner, no DOM:
//
//   node --test assets/js
import { describe, it } from "node:test"
import assert from "node:assert/strict"

import { activeSlot, normalizeCode } from "./otpInput.js"

describe("normalizeCode", () => {
  it("keeps digits", () => {
    assert.equal(normalizeCode("482913", 6), "482913")
  })

  it("drops the space or dash a pasted code has", () => {
    assert.equal(normalizeCode("482 913", 6), "482913")
    assert.equal(normalizeCode("482-913", 6), "482913")
  })

  it("drops letters", () => {
    assert.equal(normalizeCode("4a8b2", 6), "482")
  })

  it("stops at the number of slots", () => {
    assert.equal(normalizeCode("48291377", 6), "482913")
  })

  it("is empty for nothing", () => {
    assert.equal(normalizeCode("", 6), "")
    assert.equal(normalizeCode(undefined, 6), "")
  })
})

describe("activeSlot", () => {
  it("is the next empty slot", () => {
    assert.equal(activeSlot("", 6), 0)
    assert.equal(activeSlot("482", 6), 3)
  })

  it("stays on the last slot when the code is full", () => {
    assert.equal(activeSlot("482913", 6), 5)
  })
})
