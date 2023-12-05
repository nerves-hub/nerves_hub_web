import '../css/app.scss'

import 'phoenix_html'
import 'bootstrap'
import $ from 'jquery'
import { Socket } from 'phoenix'
import { LiveSocket } from 'phoenix_live_view'
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

window.deploymentPolling = (url) => {
  fetch(url, {
    headers: {
      "Accept": "application/json"
    }
  }).then((response) => response.json())
    .then((json) => {
      let inflightUpdateBadges = $("#inflight-update-badges");
      inflightUpdateBadges.empty();

      let inflightEmpty = $("#inflight-empty");
      if (json.inflight_updates.length == 0) {
        inflightEmpty.html("No inflight updates");
      } else {
        inflightEmpty.empty();
      }

      json.inflight_updates.map((inflightUpdate) => {
        let badge = $(`<span class="ff-m badge"><a href="${inflightUpdate.href}">${inflightUpdate.identifier}</a></span>`);
        inflightUpdateBadges.append(badge);
      });

      let deploymentPercentage = $("#deployment-percentage").first();
      deploymentPercentage.html(`${json.percentage}%`);
      deploymentPercentage.css("width", `${json.percentage}%`);
    });
};

document.querySelectorAll('.date-time').forEach(d => {
  d.innerHTML = dates.formatDateTime(d.innerHTML)
})
