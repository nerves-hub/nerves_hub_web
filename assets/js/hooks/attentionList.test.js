// Unit tests for when attentionList.js opens the first device in the peek.
// Runs on Node's built-in test runner:
//
//   node --test assets/js
import { describe, it } from "node:test"
import assert from "node:assert/strict"

import { shouldOpenFirst } from "./attentionList.js"

const list = (overrides = {}) => ({
  key: "|",
  openedKey: null,
  wide: true,
  peekOpen: false,
  firstId: "12",
  ...overrides,
})

describe("shouldOpenFirst", () => {
  it("opens the first device of a list it hasn't shown yet", () => {
    assert.equal(shouldOpenFirst(list()), true)
  })

  it("opens it again when the list changes", () => {
    assert.equal(shouldOpenFirst(list({ key: "failing|", openedKey: "|" })), true)
  })

  it("leaves a refreshed list alone, so a closed peek stays closed", () => {
    assert.equal(shouldOpenFirst(list({ key: "|", openedKey: "|" })), false)
  })

  it("leaves a narrow screen alone, where the peek would cover the list", () => {
    assert.equal(shouldOpenFirst(list({ wide: false })), false)
  })

  it("leaves an open peek alone", () => {
    assert.equal(shouldOpenFirst(list({ peekOpen: true })), false)
  })

  it("waits while the Filters panel is open, where the peek would open underneath", () => {
    assert.equal(shouldOpenFirst(list({ filtersOpen: true })), false)
  })

  it("does nothing for an empty list", () => {
    assert.equal(shouldOpenFirst(list({ firstId: undefined })), false)
  })
})
