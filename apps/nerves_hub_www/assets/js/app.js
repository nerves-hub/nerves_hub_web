import '../css/app.scss'

import 'phoenix_html'
import 'bootstrap'
import $ from 'jquery'
import { Socket } from 'phoenix'
import LiveSocket from 'phoenix_live_view'
import IEx from './console'

let dates = require('./dates')
const iex = new IEx()
let csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute('content')
let liveSocket = new LiveSocket('/live', Socket, {
  params: { _csrf_token: csrfToken }
})
let socket = new Socket('/socket', { params: { token: window.userToken } })

liveSocket.connect()

document.querySelectorAll('.date-time').forEach(d => {
  d.innerHTML = dates.formatDateTime(d.innerHTML)
})

if (window.location.pathname.endsWith('console')) {
  iex.start(socket)
}
