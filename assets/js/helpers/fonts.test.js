// Unit tests for waiting on a web font before drawing on a canvas. Runs on
// Node's built-in test runner, with `document.fonts` faked:
//
//   node --test assets/js
import { beforeEach, describe, it } from "node:test"
import assert from "node:assert/strict"

import { whenFontsLoaded } from "./fonts.js"

let loaded
let loads

beforeEach(() => {
  loaded = new Set()
  loads = []

  globalThis.document = {
    fonts: {
      check: font => loaded.has(font),
      load: font => {
        loads.push(font)
        return font.includes("missing")
          ? Promise.reject(new Error("NetworkError"))
          : Promise.resolve().then(() => loaded.add(font))
      }
    }
  }
})

describe("whenFontsLoaded", () => {
  it("runs straight away when every font has loaded", () => {
    loaded.add("14px Mono")
    loaded.add("bold 14px Mono")

    let ran = false
    whenFontsLoaded(["14px Mono", "bold 14px Mono"], () => (ran = true))

    assert.equal(ran, true)
    assert.deepEqual(loads, [])
  })

  it("waits for every font that hasn't loaded", async () => {
    loaded.add("14px Mono")

    const done = new Promise(resolve =>
      whenFontsLoaded(["14px Mono", "bold 14px Mono"], () =>
        resolve(loaded.has("bold 14px Mono"))
      )
    )

    assert.deepEqual(loads, ["14px Mono", "bold 14px Mono"])
    assert.equal(await done, true)
  })

  it("still runs when a font fails to load", async () => {
    const done = new Promise(resolve =>
      whenFontsLoaded(["14px missing"], () => resolve("ran"))
    )

    assert.equal(await done, "ran")
  })
})
