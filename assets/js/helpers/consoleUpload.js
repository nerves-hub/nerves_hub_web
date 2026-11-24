// Sending a file to a device's console, and telling whoever sent it how it's
// going. No DOM here, so the unit tests run on Node alone.
//
// A file goes in three stages:
//
//   1. Up to the server, a chunk at a time. Each chunk is answered once it's
//      on its way to the device, so this is measured.
//   2. Across to the device.
//   3. Saved by the device, a chunk at a time. Its console reads nothing else
//      until the whole file is saved, typing included.
//
// A device whose console channel sets `file_acks` in its metadata reports each
// chunk it saves (`file-data/ack`), then `file-data/saved` or
// `file-data/error`. An older one says nothing, so the page types a character
// and deletes it (`PROBE`), and the file is saved once the console echoes it:
// the device handles messages in order, so it can't answer the probe before
// it has saved the file.
import { CHUNK_SIZE, encodeChunk } from "./consoleFiles.js"

// How many chunks can be on their way to the server at once. Enough to keep
// the connection busy, few enough that the browser never holds the whole file
// in its send queue.
export const WINDOW = 8

// How long a chunk can wait for the server's answer. One that times out is
// counted as sent: the server may just be slow, and a chunk that really was
// lost shows up as the device never finishing.
export const PUSH_TIMEOUT = 60_000

// A character, then Delete. It leaves the line as it was.
export const PROBE = "x\u007f"

// How long a file can take before the dialog opens over the console. A small
// one is saved before then, and only the strip under the console shows.
export const OPEN_DELAY = 1000

// How long the strip says a file was saved before it goes.
export const SAVED_LINGER = 6000

// The console's echo of `PROBE`: the "x", then straight away the cursor going
// back over it, as a backspace or as a cursor-left escape (IEx draws `\e[1D`).
// Requiring the two together keeps earlier output from matching, such as the
// "x" in a prompt and a later cursor movement. Only typing "x" then Delete
// while the file was on its way still looks the same.
const PROBE_ECHO = /x(?:\u0008|\u001b\[1?D)/

// Whether what the console has printed since the probe was sent includes its
// echo.
export const probeEchoed = (output) => PROBE_ECHO.test(output)

// A file's bytes in `CHUNK_SIZE` pieces. A stream hands over whatever sizes it
// likes, so they're cut or joined to size.
export async function* chunksOf(stream, size = CHUNK_SIZE) {
  const reader = stream.getReader()
  let pending = new Uint8Array(0)

  for (;;) {
    const { done, value } = await reader.read()

    if (done) break

    const joined = new Uint8Array(pending.length + value.length)
    joined.set(pending)
    joined.set(value, pending.length)

    let offset = 0

    for (; offset + size <= joined.length; offset += size) {
      yield joined.subarray(offset, offset + size)
    }

    pending = joined.slice(offset)
  }

  if (pending.length > 0) yield pending
}

// Sends a file's chunks: `file-data/start`, the chunks numbered from 0, then
// `file-data/stop`. `push(event, payload)` resolves once the server has
// answered a chunk, and `onSent(bytes)` hears each one. Keeps no more than
// `window` chunks unanswered. Rejects if a push does, or if `aborted` does.
//
// Resolves with how many chunks were sent, once `file-data/stop` has been.
export async function sendChunks({ filename, chunks, push, onSent, aborted, window = WINDOW }) {
  const stopped = aborted ?? new Promise(() => {})
  const inFlight = new Set()
  let chunk = 0

  // Checked before every chunk, not only when the window is full, so a file
  // nobody wants any more stops at once even when the server keeps up.
  let abortedWith = null
  stopped.catch((reason) => (abortedWith = { reason }))

  push("file-data/start", { filename })

  for await (const data of chunks) {
    if (abortedWith) throw abortedWith.reason

    const bytes = data.length
    const sent = push("file-data", { filename, chunk, data: encodeChunk(data) }).then(() => {
      inFlight.delete(sent)
      onSent(bytes)
    })

    // Rejections are seen through the race below; this only keeps one that
    // loses the race from being reported as unhandled.
    sent.catch(() => {})
    inFlight.add(sent)
    chunk += 1

    if (inFlight.size >= window) await Promise.race([...inFlight, stopped])
  }

  await Promise.race([Promise.all(inFlight), stopped])

  push("file-data/stop", { filename })

  return chunk
}

const UNITS = ["B", "KB", "MB", "GB"]

const unitOf = (bytes) => {
  let unit = 0

  while (unit < UNITS.length - 1 && bytes >= 1000 ** (unit + 1)) unit += 1

  return unit
}

const inUnit = (bytes, unit) => {
  const value = bytes / 1000 ** unit

  if (unit === 0) return String(bytes)

  return value < 10 ? value.toFixed(1) : String(Math.round(value))
}

// A size as a person reads it: "812 B", "4.8 MB", "120 MB".
export const formatBytes = (bytes) => {
  const unit = unitOf(bytes)

  return `${inUnit(bytes, unit)} ${UNITS[unit]}`
}

// How far along a file is, in the whole file's unit: "3.1 of 4.8 MB".
export const formatProgress = (done, total) => {
  const unit = unitOf(total)

  return `${inUnit(done, unit)} of ${inUnit(total, unit)} ${UNITS[unit]}`
}

// A stretch of time as a clock: "0:07", "12:30", "1:02:03".
export const formatClock = (ms) => {
  const seconds = Math.max(0, Math.floor(ms / 1000))
  const s = String(seconds % 60).padStart(2, "0")
  const minutes = Math.floor(seconds / 60)

  if (minutes < 60) return `${minutes}:${s}`

  return `${Math.floor(minutes / 60)}:${String(minutes % 60).padStart(2, "0")}:${s}`
}
