import 'phoenix_html'
import 'bootstrap'
import $ from 'jquery'
import LiveSocket from 'phoenix_live_view'
let dates = require('./dates')

let liveSocket = new LiveSocket('/live')
liveSocket.connect()

document.querySelectorAll('.date-time').forEach(d => {
  d.innerHTML = dates.formatDateTime(d.innerHTML)
})

$(function() {
  $('[data-toggle="help-tooltip"]').tooltip()
})
