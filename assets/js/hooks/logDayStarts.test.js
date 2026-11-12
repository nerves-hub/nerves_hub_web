// Unit tests for which log lines logDayStarts.js marks as starting a day.
// Runs on Node's built-in test runner - no dependencies, no DOM:
//
//   node --test assets/js
import { describe, it } from "node:test"
import assert from "node:assert/strict"

import { dayStarts } from "./logDayStarts.js"

describe("dayStarts", () => {
  it("starts the first line's day", () => {
    assert.deepEqual(dayStarts(["2026-11-12"]), [true])
  })

  it("starts a day each time it changes, newest first", () => {
    assert.deepEqual(
      dayStarts(["2026-11-12", "2026-11-12", "2026-11-11", "2026-11-10"]),
      [true, false, true, true],
    )
  })

  it("marks nothing in an empty list", () => {
    assert.deepEqual(dayStarts([]), [])
  })
})
