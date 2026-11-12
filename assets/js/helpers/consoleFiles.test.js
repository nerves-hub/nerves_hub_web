// Unit tests for which device consoles can be sent a file.
// Runs on Node's built-in test runner - no DOM:
//
//   node --test assets/js
import { describe, it } from "node:test"
import assert from "node:assert/strict"

import { acceptsFiles } from "./consoleFiles.js"

describe("acceptsFiles", () => {
  it("accepts a console from 2.0.0 on", () => {
    assert.equal(acceptsFiles("2.0.0"), true)
    assert.equal(acceptsFiles("2.3.1"), true)
  })

  it("refuses a console before 2.0.0", () => {
    assert.equal(acceptsFiles("1.0.0"), false)
    assert.equal(acceptsFiles("1.9.9"), false)
  })

  it("accepts a console that sent no version, or not a semver one", () => {
    assert.equal(acceptsFiles(undefined), true)
    assert.equal(acceptsFiles(null), true)
    assert.equal(acceptsFiles("unknown"), true)
  })
})
