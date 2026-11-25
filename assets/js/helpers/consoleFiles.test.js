// Unit tests for sending a file to a device console.
// Runs on Node's built-in test runner - no DOM:
//
//   node --test assets/js
import { describe, it } from "node:test"
import assert from "node:assert/strict"

import { acceptsFiles, CHUNK_SIZE, encodeChunk } from "./consoleFiles.js"

describe("acceptsFiles", () => {
  it("accepts a console from 2.0.0 on", () => {
    assert.equal(acceptsFiles("2.0.0"), true)
    assert.equal(acceptsFiles("2.3.1"), true)
    assert.equal(acceptsFiles("v2.1.0"), true)
    assert.equal(acceptsFiles("2.0.0-rc.1"), true)
  })

  it("refuses a console before 2.0.0", () => {
    assert.equal(acceptsFiles("1.0.0"), false)
    assert.equal(acceptsFiles("1.9.9"), false)
    assert.equal(acceptsFiles("1.9.9-dev"), false)
  })

  it("accepts a console that sent no version, or one with no number", () => {
    assert.equal(acceptsFiles(undefined), true)
    assert.equal(acceptsFiles(null), true)
    assert.equal(acceptsFiles("unknown"), true)
  })
})

describe("encodeChunk", () => {
  it("matches Node's base64 for a full chunk", () => {
    const bytes = new Uint8Array(CHUNK_SIZE).map((_, i) => (i * 7) % 256)

    assert.equal(encodeChunk(bytes), Buffer.from(bytes).toString("base64"))
  })

  it("handles a chunk that isn't a whole number of slices", () => {
    const bytes = new Uint8Array(10_000).map((_, i) => (i * 13) % 256)

    assert.equal(encodeChunk(bytes), Buffer.from(bytes).toString("base64"))
  })

  it("encodes an empty chunk as an empty string", () => {
    assert.equal(encodeChunk(new Uint8Array(0)), "")
  })
})
