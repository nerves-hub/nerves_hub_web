import '../css/app.scss'

import 'phoenix_html'
import 'bootstrap'
import $ from 'jquery'
import { Socket } from 'phoenix'
import LiveSocket from 'phoenix_live_view'
import Josh from 'joshjs'

let dates = require('./dates')
let csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute('content')
let liveSocket = new LiveSocket('/live', Socket, {
  params: { _csrf_token: csrfToken }
})

liveSocket.connect()

new Josh()

$(function() {
  $('.custom-upload-input').on('change', function() {
    let fileName = $(this)
      .val()
      .split('\\')
      .pop()
    $(this)
      .siblings('.custom-upload-label')
      .removeClass('not-selected')
      .addClass('selected')
      .html("Selected File: <div class='file-name'>" + fileName + '</div>')
  })
})

document.querySelectorAll('.date-time').forEach(d => {
  d.innerHTML = dates.formatDateTime(d.innerHTML)
})
