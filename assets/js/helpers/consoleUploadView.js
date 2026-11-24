// Sends the files dropped or picked on a device's console, one at a time, and
// shows how each is going in the dialog over the console and the strip under
// it (both rendered by `NervesHubWeb.Components.DevicePage.ConsoleTab`).
//
// The markup holds every state's words. This sets `data-state` on both
// (uploading, saving, saved or failed), `data-step` on each step (todo,
// active, done or failed), and `data-acks` when the device reports what it
// saves, and fills in the `data-upload-field`s and `data-upload-bar`s.
import {
  chunksOf,
  formatBytes,
  formatClock,
  formatProgress,
  OPEN_DELAY,
  PROBE,
  probeEchoed,
  PUSH_TIMEOUT,
  SAVED_LINGER,
  sendChunks
} from "./consoleUpload.js"

const DISCONNECTED = "The console disconnected before the file was saved."
const REFUSED = "The server turned the file down."
const UNREADABLE = "The browser couldn't read the file."

// `channel` is the user's console channel, `fileAcks()` whether the device's
// console reports what it saves (its metadata's `file_acks`), and `focus()`
// gives the terminal focus back.
export function setupUploads({ frame, channel, fileAcks, focus }) {
  const dialog = frame.querySelector("[data-upload-dialog]")
  const strip = frame.querySelector("[data-upload-strip]")
  const roots = [dialog, strip].filter(Boolean)

  if (roots.length === 0) return { send: () => {}, output: () => {}, teardown: () => {} }

  const queue = []
  let batch = { total: 0, index: 0, hidden: false }
  let current = null
  let openTimer = null
  let clockTimer = null
  let lingerTimer = null

  const each = (selector, fun) => roots.forEach((root) => root.querySelectorAll(selector).forEach(fun))

  const setField = (name, text) => each(`[data-upload-field="${name}"]`, (el) => (el.textContent = text))

  const setBar = (name, done, total) => {
    const fraction = total > 0 ? Math.min(1, done / total) : 1
    each(`[data-upload-bar="${name}"]`, (el) => (el.style.width = `${fraction * 100}%`))
  }

  const setStep = (step, state) => each(`[data-upload-step="${step}"]`, (el) => (el.dataset.step = state))

  const STEPS = {
    uploading: ["active", "todo"],
    saving: ["done", "active"],
    saved: ["done", "done"],
    "failed-upload": ["failed", "todo"],
    "failed-save": ["done", "failed"]
  }

  const setState = (state, failedAt) => {
    roots.forEach((root) => (root.dataset.state = state))

    const [upload, save] = STEPS[failedAt ? `failed-${failedAt}` : state]
    setStep("upload", upload)
    setStep("save", save)
  }

  const dialogOpen = () => dialog && !dialog.hidden

  const openDialog = () => {
    if (dialog) dialog.hidden = false
  }

  const closeDialog = () => {
    if (dialog) dialog.hidden = true
  }

  const clearTimers = () => {
    clearTimeout(openTimer)
    clearInterval(clockTimer)
    clearTimeout(lingerTimer)
  }

  const tick = () => {
    if (current?.state === "saving") setField("clock", formatClock(Date.now() - current.uploadedAt))
  }

  const next = () => {
    if (queue.length === 0) {
      batch = { total: 0, index: 0, hidden: batch.hidden }
      return
    }

    const file = queue.shift()
    const acks = fileAcks()
    let abort
    const aborted = new Promise((_resolve, reject) => (abort = reject))
    aborted.catch(() => {})

    current = { file, acks, abort, state: "uploading", startedAt: Date.now(), sent: 0, saved: 0, output: "" }
    batch.index += 1

    clearTimers()
    roots.forEach((root) => (acks ? (root.dataset.acks = "") : delete root.dataset.acks))
    setState("uploading")
    setField("name", file.name)
    setField("size", formatBytes(file.size))
    setField("count", batch.total > 1 ? ` · ${batch.index} of ${batch.total}` : "")
    setField("sent", formatProgress(0, file.size))
    setField("saved", formatProgress(0, file.size))
    setField("reason", "")
    setBar("sent", 0, file.size)
    setBar("saved", 0, file.size)

    if (strip) strip.hidden = false
    if (!batch.hidden && !dialogOpen()) openTimer = setTimeout(openDialog, OPEN_DELAY)
    clockTimer = setInterval(tick, 250)

    const upload = current

    sendChunks({
      filename: file.name,
      chunks: chunksOf(file.stream()),
      push,
      aborted,
      onSent: (bytes) => {
        upload.sent += bytes
        setField("sent", formatProgress(upload.sent, file.size))
        setBar("sent", upload.sent, file.size)
      }
    })
      .then(() => {
        if (current !== upload) return

        upload.state = "saving"
        upload.uploadedAt = Date.now()
        setState("saving")
        tick()

        // The device answers this only once it has saved the file, since it
        // reads its messages in order.
        if (!upload.acks) channel.push("dn", { data: PROBE })
      })
      .catch((reason) => fail(upload, "upload", typeof reason === "string" ? reason : UNREADABLE))
  }

  // Resolves once the server has answered a chunk. One that times out counts
  // as sent (see `PUSH_TIMEOUT`).
  const push = (event, payload) => {
    if (event !== "file-data") {
      channel.push(event, payload)
      return undefined
    }

    return new Promise((resolve, reject) => {
      channel
        .push(event, payload, PUSH_TIMEOUT)
        .receive("ok", resolve)
        .receive("error", () => reject(REFUSED))
        .receive("timeout", resolve)
    })
  }

  const finish = (upload) => {
    if (current !== upload || upload.state === "saved") return

    const now = Date.now()
    upload.state = "saved"
    upload.uploadedAt ??= now

    clearTimers()
    setState("saved")
    setField("uploaded-in", formatClock(upload.uploadedAt - upload.startedAt))
    setField("saved-in", formatClock(now - upload.uploadedAt))
    setField("total-in", `${formatBytes(upload.file.size)} · ${formatClock(now - upload.startedAt)}`)

    if (queue.length > 0) {
      next()
    } else if (!dialogOpen()) {
      lingerTimer = setTimeout(dismiss, SAVED_LINGER)
    }
  }

  const fail = (upload, stage, reason) => {
    if (current !== upload || upload.state === "saved" || upload.state === "failed") return

    upload.state = "failed"
    upload.abort(reason)
    queue.length = 0

    clearTimers()
    setState("failed", stage)
    setField("reason", reason)
  }

  const inProgress = () => current && (current.state === "uploading" || current.state === "saving")

  const dismiss = () => {
    clearTimeout(lingerTimer)
    closeDialog()
    if (strip) strip.hidden = true
    if (!inProgress()) batch.hidden = false
  }

  // Hide leaves the strip; the others put the console back as it was.
  const actions = {
    hide: () => {
      clearTimeout(openTimer)
      batch.hidden = true
      closeDialog()
      focus()
    },
    open: () => {
      clearTimeout(openTimer)
      batch.hidden = false
      openDialog()
    },
    close: () => {
      dismiss()
      focus()
    },
    dismiss
  }

  const onClick = (event) => {
    const button = event.target.closest("[data-upload-action]")
    if (button) actions[button.dataset.uploadAction]?.()
  }

  // Escape would otherwise go to the terminal, and on to the device.
  const onKeydown = (event) => {
    if (event.key !== "Escape" || !dialogOpen()) return

    event.preventDefault()
    event.stopPropagation()
    inProgress() ? actions.hide() : actions.close()
  }

  roots.forEach((root) => root.addEventListener("click", onClick))
  frame.addEventListener("keydown", onKeydown, true)

  const byFilename = (handler) => (payload) => {
    if (current && current.acks && payload.filename === current.file.name) handler(current, payload)
  }

  channel.on(
    "file-data/ack",
    byFilename((upload, { bytes }) => {
      upload.saved = Math.max(upload.saved, bytes ?? 0)
      setField("saved", formatProgress(upload.saved, upload.file.size))
      setBar("saved", upload.saved, upload.file.size)
    })
  )

  channel.on("file-data/saved", byFilename(finish))

  channel.on(
    "file-data/error",
    byFilename((upload, { reason }) =>
      fail(upload, "save", reason ? `The device couldn't save it: ${reason}.` : "The device couldn't save it.")
    )
  )

  const lost = () => {
    if (inProgress()) fail(current, current.state === "uploading" ? "upload" : "save", DISCONNECTED)
  }

  channel.onError(lost)
  channel.onClose(lost)

  return {
    // Queues files to send, after any already on their way.
    send(files) {
      if (files.length === 0) return

      if (!inProgress()) {
        current = null
        batch = { total: 0, index: 0, hidden: false }
      }

      queue.push(...files)
      batch.total += files.length

      if (!current) next()
    },

    // What the console printed, for the probe's echo.
    output(data) {
      const upload = current
      if (!upload || upload.acks || upload.state !== "saving") return

      upload.output = (upload.output + data).slice(-256)
      if (probeEchoed(upload.output)) finish(upload)
    },

    teardown() {
      clearTimers()
      roots.forEach((root) => root.removeEventListener("click", onClick))
      frame.removeEventListener("keydown", onKeydown, true)
    }
  }
}
