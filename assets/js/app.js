import '../css/app.scss'

import 'phoenix_html'
import 'bootstrap'
import { Socket } from 'phoenix'
import { LiveSocket } from 'phoenix_live_view'
import Josh from 'joshjs'

let dates = require('./dates')

let Hooks = {}

Hooks.SharedSecretClipboardClick = {
  mounted() {
    const parent = this.el
    this.el.addEventListener('click', () => {
      const secret = document.getElementById('shared-secret-' + parent.value)
        .value
      if (typeof ClipboardItem && navigator.clipboard.write) {
        // NOTE: Safari locks down the clipboard API to only work when triggered
        //   by a direct user interaction. You can't use it async in a promise.
        //   But! You can wrap the promise in a ClipboardItem, and give that to
        //   the clipboard API.
        //   Found this on https://developer.apple.com/forums/thread/691873
        const clipboardItem = new ClipboardItem({
          'text/plain': secret
        })
        navigator.clipboard.write([clipboardItem])
        confirm('Secret copied to your clipboard')
      } else {
        // NOTE: Firefox has support for ClipboardItem and navigator.clipboard.write,
        //   but those are behind `dom.events.asyncClipboard.clipboardItem` preference.
        //   Good news is that other than Safari, Firefox does not care about
        //   Clipboard API being used async in a Promise.
        navigator.clipboard.writeText(secret)
        confirm('Secret copied to your clipboard')
      }
    })
  }
}

Hooks.LocalTime = {
  mounted() {
    this.updated()
  },
  updated() {
    let dt = new Date(this.el.textContent.trim())

    dt.setSeconds(null)

    let formatted = new Intl.DateTimeFormat('en-GB', {
      dateStyle: 'medium',
      timeStyle: 'long',
      timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone,
      hour12: true
    }).format(dt)

    this.el.textContent = formatted
  }
}

Hooks.SimpleDate = {
  mounted() {
    this.updated()
  },
  updated() {
    this.el.textContent = dates.formatDate(this.el.textContent)
  }
}

let csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute('content')
let liveSocket = new LiveSocket('/live', Socket, {
  params: { _csrf_token: csrfToken },
  hooks: Hooks
})

liveSocket.connect()

new Josh()

document.querySelectorAll('.date-time').forEach(d => {
  d.innerHTML = dates.formatDateTime(d.innerHTML)
})

window.addEventListener('phx:sharedsecret:created', () => {
  confirm('A new Shared Secret has been created.')
})

window.addEventListener('ca:edit:jitp', () => {
  const checked = document.getElementById('jitp_toggle_ui').checked

  document.getElementById('jitp-delete').value = !checked

  if (checked) {
    document.getElementById('jitp_form').classList.remove('hidden')
  } else {
    document.getElementById('jitp_form').classList.add('hidden')
  }
})

window.addEventListener('ca:new:jitp', () => {
  const checked = document.getElementById('jitp_toggle_ui').checked

  document.getElementById('jitp_toggle').value = checked

  if (checked) {
    document.getElementById('jitp_form').classList.remove('hidden')
  } else {
    document.getElementById('jitp_form').classList.add('hidden')
  }
})
