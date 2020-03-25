import '../css/app.scss'

import 'phoenix_html'
import 'bootstrap'
import $ from 'jquery'
import { Socket } from 'phoenix'
import LiveSocket from 'phoenix_live_view'

let dates = require('./dates')
let csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute('content')
let liveSocket = new LiveSocket('/live', Socket, {
  params: { _csrf_token: csrfToken }
})

liveSocket.connect()

document.querySelectorAll('.date-time').forEach(d => {
  d.innerHTML = dates.formatDateTime(d.innerHTML)
})

$(function() {
  $('[data-toggle="help-tooltip"]').tooltip()
})
