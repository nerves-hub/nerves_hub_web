import '../css/app.scss'

import 'phoenix_html'
import 'bootstrap'
import $ from 'jquery'
import { Socket } from 'phoenix'
import { LiveSocket } from 'phoenix_live_view'
import Josh from 'joshjs'

let dates = require('./dates')

let Hooks = {}

Hooks.LocalTime = {
  mounted() {
    this.updated()
  },
  updated() {
    let dt = new Date(this.el.textContent)
    this.el.textContent =
      dt.toLocaleString() +
      ' ' +
      Intl.DateTimeFormat().resolvedOptions().timeZone
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

window.deploymentPolling = url => {
  fetch(url, {
    headers: {
      Accept: 'application/json'
    }
  })
    .then(response => response.json())
    .then(json => {
      let inflightUpdateBadges = $('#inflight-update-badges')
      inflightUpdateBadges.empty()

      let inflightEmpty = $('#inflight-empty')
      if (json.inflight_updates.length == 0) {
        inflightEmpty.html('No inflight updates')
      } else {
        inflightEmpty.empty()
      }

      json.inflight_updates.map(inflightUpdate => {
        let badge = $(
          `<span class="ff-m badge"><a href="${inflightUpdate.href}">${inflightUpdate.identifier}</a></span>`
        )
        inflightUpdateBadges.append(badge)
      })

      let deploymentPercentage = $('#deployment-percentage').first()
      deploymentPercentage.html(`${json.percentage}%`)
      deploymentPercentage.css('width', `${json.percentage}%`)
    })
}

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
