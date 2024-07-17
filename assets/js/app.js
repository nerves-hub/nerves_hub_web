import '../css/app.scss'

import 'phoenix_html'
import 'bootstrap'
import { Socket } from 'phoenix'
import { LiveSocket } from 'phoenix_live_view'

import hljs from 'highlight.js/lib/core'
import bash from 'highlight.js/lib/languages/bash'
import elixir from 'highlight.js/lib/languages/elixir'
import plaintext from 'highlight.js/lib/languages/plaintext'
import shell from 'highlight.js/lib/languages/shell'
hljs.registerLanguage('bash', bash)
hljs.registerLanguage('elixir', elixir)
hljs.registerLanguage('plaintext', plaintext)
hljs.registerLanguage('shell', shell)

import 'highlight.js/styles/stackoverflow-light.css'

let dates = require('./dates')

let Hooks = {}

Hooks.HighlightCode = {
  mounted() {
    this.updated()
  },
  updated() {
    hljs.highlightElement(this.el)
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

document.querySelectorAll('.date-time').forEach(d => {
  d.innerHTML = dates.formatDateTime(d.innerHTML)
})

window.addEventListener('phx:sharedsecret:clipcopy', event => {
  if ('clipboard' in navigator) {
    const text = event.detail.secret
    navigator.clipboard.writeText(text).then(
      () => {
        confirm('Content copied to clipboard')
      },
      () => {
        alert('Failed to copy')
      }
    )
  } else {
    alert('Sorry, your browser does not support clipboard copy.')
  }
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
