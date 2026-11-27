// Whether a device's console can be sent a file, from the console version it
// joined with (the channel's "metadata" message). Consoles before 2.0.0 can't
// take one. A device that sent no version, or one with no number in it, is
// given the benefit of the doubt: refusing a drop it could take is worse than
// sending one it ignores.
//
// Only the major version matters, read as `semver.coerce` would: the first
// run of digits. No `semver` import, so the unit tests run without an npm
// install, as CI runs them.
export const acceptsFiles = (version) => {
  const major = String(version ?? "").match(/\d+/)

  return major === null || Number(major[0]) >= 2
}

// How much of a file goes in each "file-data" message. The device saves each
// message before it reads the next, typing included, and opens and closes the
// file for every one, so larger chunks give it back its console sooner.
export const CHUNK_SIZE = 64 * 1024

// `String.fromCharCode` takes a byte per argument, and engines cap how many
// arguments a call can take (JavaScriptCore at 65,536), so a chunk is turned
// into a string a slice at a time.
const SLICE = 8 * 1024

// Base64 of a chunk of a file, as the device's console expects it.
export const encodeChunk = (bytes) => {
  let binary = ""

  for (let i = 0; i < bytes.length; i += SLICE) {
    binary += String.fromCharCode.apply(null, bytes.subarray(i, i + SLICE))
  }

  return btoa(binary)
}
