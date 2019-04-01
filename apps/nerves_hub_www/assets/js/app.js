import 'phoenix_html'
import 'bootstrap'
import LiveSocket from 'phoenix_live_view'

let liveSocket = new LiveSocket('/live')
liveSocket.connect()

if (window.location.pathname === '/devices') {
  require('./socket')
  let dates = require('./dates')

  document.querySelectorAll('.date-time').forEach(d => {
    d.innerHTML = dates.formatLastCommunication(d.innerHTML)
  })
}
