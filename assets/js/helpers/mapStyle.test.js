// Unit tests for picking and tracking the device location map's Mapbox style.
// Runs on Node's built-in test runner, with just enough of `document` and
// `window` faked for the helper:
//
//   node --test assets/js
import { beforeEach, describe, it } from "node:test"
import assert from "node:assert/strict"

import { mapboxStyleUrl, trackMapStyle } from "./mapStyle.js"

let theme

beforeEach(() => {
  theme = "dark"
  globalThis.document = { documentElement: { getAttribute: () => theme } }
  globalThis.window = new EventTarget()
})

describe("mapboxStyleUrl", () => {
  it("is the Mapbox style for a picked style", () => {
    assert.equal(mapboxStyleUrl("satellite_streets"), "mapbox://styles/mapbox/satellite-streets-v12")
  })

  it("follows the theme with no pick", () => {
    assert.equal(mapboxStyleUrl(undefined), "mapbox://styles/mapbox/dark-v11")

    theme = "light"
    assert.equal(mapboxStyleUrl(undefined), "mapbox://styles/mapbox/light-v11")
  })

  it("follows the theme for a style it doesn't know", () => {
    assert.equal(mapboxStyleUrl("watercolor"), "mapbox://styles/mapbox/dark-v11")
    assert.equal(mapboxStyleUrl("constructor"), "mapbox://styles/mapbox/dark-v11")
  })
})

describe("trackMapStyle", () => {
  function setup(mapStyle) {
    const el = { dataset: { mapStyle } }
    const map = { styles: [], setStyle: (url) => map.styles.push(url) }
    return { el, map, tracker: trackMapStyle(el, map) }
  }

  it("restyles the map when the pick changes", () => {
    const { el, map, tracker } = setup(undefined)

    el.dataset.mapStyle = "satellite"
    tracker.apply()

    assert.deepEqual(map.styles, ["mapbox://styles/mapbox/satellite-v9"])
  })

  it("leaves the map alone when nothing changed", () => {
    const { map, tracker } = setup("outdoors")

    tracker.apply()

    assert.deepEqual(map.styles, [])
  })

  it("follows a theme change only with no pick", () => {
    const followed = setup(undefined)
    const picked = setup("streets")

    theme = "light"
    window.dispatchEvent(new Event("themeUpdated"))

    assert.deepEqual(followed.map.styles, ["mapbox://styles/mapbox/light-v11"])
    assert.deepEqual(picked.map.styles, [])
  })

  it("stops following the theme once stopped", () => {
    const { map, tracker } = setup(undefined)

    tracker.stop()
    theme = "light"
    window.dispatchEvent(new Event("themeUpdated"))

    assert.deepEqual(map.styles, [])
  })
})
