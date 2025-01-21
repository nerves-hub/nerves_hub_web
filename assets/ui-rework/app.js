import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import topbar from "topbar"
import { createLiveToastHook } from "live_toast"
import "chartjs-adapter-date-fns"

import TimeAgo from "javascript-time-ago"
import en from "javascript-time-ago/locale/en"

import Console from "./hooks/console.js"
import SharedSecretClipboardClick from "./hooks/sharedSecretClipboardClick.js"
import Chart from "./hooks/chart.js"
import HighlightCode from "./hooks/highlightCode.js"
import UpdatingTimeAgo from "./hooks/updatingTimeAgo.js"
import LocalTime from "./hooks/localTime.js"
import SimpleDate from "./hooks/simpleDate.js"
import WorldMap from "./hooks/worldMap.js"
import DeviceLocationMap from "./hooks/deviceLocationMap.js"

import dates from "../js/dates"

TimeAgo.addDefaultLocale(en)

let csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: {
    Console,
    SharedSecretClipboardClick,
    Chart,
    HighlightCode,
    UpdatingTimeAgo,
    LocalTime,
    SimpleDate,
    WorldMap,
    DeviceLocationMap,
    LiveToast: createLiveToastHook()
  }
})

// Show progress bar on live navigation and form submits
topbar.config({
  barColors: { 0: "#6366F1" },
  barThickness: 5,
  shadowColor: "rgba(0, 0, 0, .3)"
})

window.addEventListener("phx:page-loading-start", () => {
  topbar.show(300)
})
window.addEventListener("phx:page-loading-stop", () => {
  topbar.hide()
})

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
