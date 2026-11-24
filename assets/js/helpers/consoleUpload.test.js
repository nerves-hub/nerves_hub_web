// Unit tests for sending a file to a device console and showing how it goes.
// Runs on Node's built-in test runner - no DOM:
//
//   node --test assets/js
import { describe, it } from "node:test"
import assert from "node:assert/strict"

import {
  chunksOf,
  formatBytes,
  formatClock,
  formatProgress,
  PROBE,
  probeEchoed,
  sendChunks
} from "./consoleUpload.js"

const streamOf = (...parts) =>
  new ReadableStream({
    start(controller) {
      for (const part of parts) controller.enqueue(Uint8Array.from(part))
      controller.close()
    }
  })

const collect = async (iterable) => {
  const out = []
  for await (const item of iterable) out.push([...item])
  return out
}

// A push that answers when told to, recording everything sent.
const fakeServer = () => {
  const sent = []
  const waiting = []

  const push = (event, payload) => {
    sent.push({ event, payload })

    if (event !== "file-data") return undefined

    return new Promise((resolve, reject) => waiting.push({ resolve, reject }))
  }

  const answer = () => waiting.shift().resolve()
  const refuse = () => waiting.shift().reject(new Error("refused"))
  const settle = () => new Promise((resolve) => setImmediate(resolve))

  return { push, sent, waiting, answer, refuse, settle }
}

describe("chunksOf", () => {
  it("cuts and joins whatever the stream gives into chunks of the size", async () => {
    const chunks = await collect(chunksOf(streamOf([1, 2, 3], [4, 5], [6, 7, 8, 9, 10]), 4))

    assert.deepEqual(chunks, [[1, 2, 3, 4], [5, 6, 7, 8], [9, 10]])
  })

  it("gives nothing for an empty file", async () => {
    assert.deepEqual(await collect(chunksOf(streamOf(), 4)), [])
  })
})

describe("sendChunks", () => {
  it("sends start, the numbered chunks, then stop", async () => {
    const server = fakeServer()
    const sent = []

    const done = sendChunks({
      filename: "a.bin",
      chunks: chunksOf(streamOf([1, 2, 3, 4, 5]), 2),
      push: server.push,
      onSent: (bytes) => sent.push(bytes),
      window: 8
    })

    await server.settle()
    while (server.waiting.length > 0) server.answer()

    assert.equal(await done, 3)
    assert.deepEqual(sent, [2, 2, 1])
    assert.deepEqual(
      server.sent.map(({ event, payload }) => [event, payload.chunk]),
      [
        ["file-data/start", undefined],
        ["file-data", 0],
        ["file-data", 1],
        ["file-data", 2],
        ["file-data/stop", undefined]
      ]
    )
    assert.equal(server.sent[1].payload.data, btoa(String.fromCharCode(1, 2)))
  })

  it("keeps no more than the window unanswered", async () => {
    const server = fakeServer()

    const done = sendChunks({
      filename: "a.bin",
      chunks: chunksOf(streamOf([1, 2, 3, 4, 5, 6]), 1),
      push: server.push,
      onSent: () => {},
      window: 2
    })

    await server.settle()
    assert.equal(server.waiting.length, 2)

    server.answer()
    await server.settle()
    assert.equal(server.waiting.length, 2)
    assert.equal(server.sent.filter(({ event }) => event === "file-data").length, 3)

    while (server.waiting.length > 0) {
      server.answer()
      await server.settle()
    }

    assert.equal(await done, 6)
    assert.equal(server.sent.at(-1).event, "file-data/stop")
  })

  it("stops, without sending stop, when the server refuses a chunk", async () => {
    const server = fakeServer()

    const done = sendChunks({
      filename: "a.bin",
      chunks: chunksOf(streamOf([1, 2, 3]), 1),
      push: server.push,
      onSent: () => {},
      window: 1
    })

    await server.settle()
    server.refuse()

    await assert.rejects(done, /refused/)
    assert.ok(!server.sent.some(({ event }) => event === "file-data/stop"))
  })

  it("stops when aborted while waiting on the server", async () => {
    const server = fakeServer()
    let abort
    const aborted = new Promise((_resolve, reject) => (abort = reject))

    const done = sendChunks({
      filename: "a.bin",
      chunks: chunksOf(streamOf([1, 2, 3]), 1),
      push: server.push,
      onSent: () => {},
      aborted,
      window: 1
    })

    await server.settle()
    abort(new Error("closed"))

    await assert.rejects(done, /closed/)
    assert.ok(!server.sent.some(({ event }) => event === "file-data/stop"))
  })
})

describe("probeEchoed", () => {
  it("sees IEx's echo of the probe", () => {
    assert.equal(probeEchoed("x\u001b[1D \u001b[1D\u001b[8D\u001b[J" + "iex(3)> "), true)
  })

  it("sees a shell that echoes Delete as a backspace", () => {
    assert.equal(probeEchoed("x\u0008 \u0008"), true)
  })

  it("waits for the cursor to go back over the x", () => {
    assert.equal(probeEchoed(""), false)
    assert.equal(probeEchoed("x"), false)
    assert.equal(probeEchoed("hello\r\n"), false)
  })

  it("is what the probe types", () => {
    assert.equal(PROBE, "x\u007f")
  })
})

describe("formatting", () => {
  it("writes sizes in the largest unit they reach", () => {
    assert.equal(formatBytes(812), "812 B")
    assert.equal(formatBytes(4_800_000), "4.8 MB")
    assert.equal(formatBytes(120_400_000), "120 MB")
    assert.equal(formatBytes(1_500_000_000), "1.5 GB")
  })

  it("writes progress in the whole file's unit", () => {
    assert.equal(formatProgress(3_100_000, 4_800_000), "3.1 of 4.8 MB")
    assert.equal(formatProgress(200_000, 4_800_000), "0.2 of 4.8 MB")
    assert.equal(formatProgress(10, 812), "10 of 812 B")
  })

  it("writes durations as a clock", () => {
    assert.equal(formatClock(0), "0:00")
    assert.equal(formatClock(7_400), "0:07")
    assert.equal(formatClock(750_000), "12:30")
    assert.equal(formatClock(3_723_000), "1:02:03")
  })
})
