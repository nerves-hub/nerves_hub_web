// Unit tests for where activeTabInView.js scrolls a strip of tabs, and when
// it counts the strip as scrolled to its end.
// Runs on Node's built-in test runner - no dependencies, no DOM:
//
//   node --test assets/js
//
// Reading positions from the page and setting the strip's scroll is left to a
// real browser.
import { describe, it } from "node:test"
import assert from "node:assert/strict"

import { atEnd, scrollLeftFor } from "./activeTabInView.js"

describe("scrollLeftFor", () => {
  it("leaves a tab that is already in view", () => {
    assert.equal(
      scrollLeftFor({
        tabStart: 4,
        tabWidth: 110,
        viewWidth: 375,
        scrollLeft: 0,
        fade: 40,
      }),
      null,
    )
  })

  it("centres a tab past the right edge", () => {
    // Integrations on a 375px phone: 543 to 672 in a 780px strip.
    assert.equal(
      scrollLeftFor({
        tabStart: 543,
        tabWidth: 129,
        viewWidth: 375,
        scrollLeft: 0,
        fade: 40,
      }),
      420,
    )
  })

  it("centres a tab under the fade at the right edge", () => {
    assert.equal(
      scrollLeftFor({
        tabStart: 250,
        tabWidth: 100,
        viewWidth: 375,
        scrollLeft: 0,
        fade: 40,
      }),
      113,
    )
  })

  it("centres a tab scrolled out past the left edge", () => {
    assert.equal(
      scrollLeftFor({
        tabStart: 400,
        tabWidth: 90,
        viewWidth: 375,
        scrollLeft: 500,
        fade: 40,
      }),
      258,
    )
  })

  it("never asks for a scroll before the strip's start", () => {
    assert.equal(
      scrollLeftFor({
        tabStart: 10,
        tabWidth: 90,
        viewWidth: 375,
        scrollLeft: 200,
      }),
      0,
    )
  })
})

describe("atEnd", () => {
  it("is false at the start of a strip that scrolls", () => {
    assert.equal(
      atEnd({ scrollLeft: 0, viewWidth: 375, scrollWidth: 780 }),
      false,
    )
  })

  it("is true scrolled to the end, even a fraction of a pixel past or short of it", () => {
    assert.equal(
      atEnd({ scrollLeft: 405.5, viewWidth: 375, scrollWidth: 780 }),
      true,
    )
    assert.equal(
      atEnd({ scrollLeft: 404.5, viewWidth: 375, scrollWidth: 780 }),
      true,
    )
  })

  it("is true for a strip whose tabs all fit", () => {
    assert.equal(
      atEnd({ scrollLeft: 0, viewWidth: 900, scrollWidth: 900 }),
      true,
    )
  })
})
