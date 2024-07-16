import '../css/app.scss'

import 'phoenix_html'
import 'bootstrap'
import { Socket } from 'phoenix'
import { LiveSocket } from 'phoenix_live_view'
import Josh from 'joshjs'

import TimeAgo from 'javascript-time-ago'
import en from 'javascript-time-ago/locale/en'

TimeAgo.addDefaultLocale(en)

let dates = require('./dates')

let Hooks = {}

Hooks.UpdatingTimeAgo = {
  updateTimer: null,
  mounted() {
    this.updateTimer = null
    this.updated()
  },
  updated(element) {
    let hook = arguments.length > 0 ? element : this

    if (hook.updateTimer) {
      clearTimeout(hook.updateTimer)
    }

    const timeAgo = new TimeAgo('en-US')

    let dtString = hook.el.dateTime
    let dt = new Date(dtString)

    // Format the date.
    // const [formattedDate, timeToNextUpdate] = timeAgo.format(dt, 'round', {
    //   getTimeToNextUpdate: true
    // })

    const formattedDate = timeAgo.format(dt, 'round')

    hook.el.textContent = formattedDate

    // https://www.npmjs.com/package/javascript-time-ago#update-interval
    // let interval = Math.min(timeToNextUpdate || 60 * 1000, 2147483647)
    let interval = 1000

    hook.updateTimer = setTimeout(hook.updated, interval, hook)
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
      timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone,
      day: 'numeric',
      month: 'short',
      year: 'numeric',
      hour: 'numeric',
      minute: 'numeric',
      hourCycle: 'h12'
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
