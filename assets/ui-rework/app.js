import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import topbar from "topbar"
import "chartjs-adapter-date-fns"

import TimeAgo from "javascript-time-ago"
import en from "javascript-time-ago/locale/en"

import Chart from "./hooks/chart.js"
import Console from "./hooks/console.js"
import DeviceLocationMap from "./hooks/deviceLocationMap.js"
import DeviceLocationMapWithGeocoder from "./hooks/deviceLocationMapWithGeocoder.js"
import Flash from "./hooks/flash.js"
import HighlightCode from "./hooks/highlightCode.js"
import LocalShell from "./hooks/localShell.js"
import LocalTime from "./hooks/localTime.js"
import LogLineLocalTime from "./hooks/logLineLocalTime.js"
import SharedSecretClipboardClick from "./hooks/sharedSecretClipboardClick.js"
import SimpleDate from "./hooks/simpleDate.js"
import SupportScriptOutput from "./hooks/supportScriptOutput.js"
import ToolTip from "./hooks/toolTip.js"
import UpdatingTimeAgo from "./hooks/updatingTimeAgo.js"
import WorldMap from "./hooks/worldMap.js"

import dates from "../js/dates"

TimeAgo.addDefaultLocale(en)

let execJS = (selector, attr) => {
  document
    .querySelectorAll(selector)
    .forEach(el => liveSocket.execJS(el, el.getAttribute(attr)))
}

let csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: {
    Chart,
    Console,
    DeviceLocationMap,
    DeviceLocationMapWithGeocoder,
    Flash,
    HighlightCode,
    LocalShell,
    LocalTime,
    LogLineLocalTime,
    SharedSecretClipboardClick,
    SimpleDate,
    SupportScriptOutput,
    ToolTip,
    UpdatingTimeAgo,
    WorldMap
  }
})

// Show progress bar on live navigation and form submits
topbar.config({
  barColors: { 0: "#6366F1" },
  barThickness: 5,
  shadowColor: "rgba(0, 0, 0, .3)"
})

window.addEventListener("phx:page-loading-start", info => {
  if (info.detail.kind == "initial") {
    document.querySelectorAll(".tab-content").forEach(el => {
      el.classList.remove("opacity-0")
    })
  }

  if (info.detail.kind == "patch") {
    document.querySelectorAll(".tab-content").forEach(el => {
      el.classList.add("phx-click-loading")
    })
  }

  topbar.show(300)
})
window.addEventListener("phx:page-loading-stop", () => {
  document.querySelectorAll(".tab-content").forEach(el => {
    el.classList.remove("phx-click-loading")
  })

  topbar.hide()
})

// borrowed from https://github.com/fly-apps/live_beats/blob/master/assets/js/app.js#L330
// this guards against the flash not hiding after reconnection, possibly due to the browser
// not passing along js events.
liveSocket.getSocket().onOpen(() => execJS("#connection-status", "js-hide"))
liveSocket.getSocket().onError(() => execJS("#connection-status", "js-show"))
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

document.querySelectorAll(".date-time").forEach(d => {
  d.innerHTML = dates.formatDateTime(d.innerHTML)
})

window.addEventListener("ca:edit:jitp", () => {
  const checked = document.getElementById("jitp_toggle_ui").checked

  document.getElementById("jitp-delete").value = !checked

  if (checked) {
    document.getElementById("jitp_form").classList.remove("hidden")
  } else {
    document.getElementById("jitp_form").classList.add("hidden")
  }
})

window.addEventListener("ca:new:jitp", () => {
  const checked = document.getElementById("jitp_toggle_ui").checked

  document.getElementById("jitp_toggle").value = checked

  if (checked) {
    document.getElementById("jitp_form").classList.remove("hidden")
  } else {
    document.getElementById("jitp_form").classList.add("hidden")
  }
})
