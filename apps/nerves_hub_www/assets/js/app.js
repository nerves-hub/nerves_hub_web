import 'phoenix_html'
import 'bootstrap'

if (window.location.pathname === '/devices') {
  require('./socket')
  let dates = require('./dates')

  document.querySelectorAll('.date-time').forEach(d => {
    d.innerHTML = dates.formatLastCommunication(d.innerHTML)
  })
}
