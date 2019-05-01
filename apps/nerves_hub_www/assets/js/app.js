import 'phoenix_html'
import 'bootstrap'
import LiveSocket from 'phoenix_live_view'
let dates = require('./dates')

let liveSocket = new LiveSocket('/live')
liveSocket.connect()

document.querySelectorAll('.date-time').forEach(d => {
  d.innerHTML = dates.formatDateTime(d.innerHTML)
})
