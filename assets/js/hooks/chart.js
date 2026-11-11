import Chart from "chart.js/auto"
import zoomPlugin from "chartjs-plugin-zoom"
import { format } from "date-fns"
import { whenFontsLoaded } from "../helpers/fonts.js"

// A metric's history on the device Health tab: one line over the selected
// time frame, with the device's health profile thresholds drawn across it as
// dashed lines and the area past the warning threshold tinted. Hovering puts a
// crosshair on the nearest reading; dragging across a chart zooms every chart
// on the tab to that span.
//
// The element carries:
//   data-key          the metric key, which server events are addressed by
//   data-metrics      the readings, as [{x: unix ms, y: value}]
//   data-thresholds   {operator, warning, alert}, or null without a profile
//   data-max          the top of the scale to start from, or empty
//   data-value-unit   "%", "°C", "MB" or empty, for the axis and tooltip
//   data-mintime / data-maxtime   the time frame's bounds
//   data-time-unit    "minute", "hour" or "day", for the axis ticks

Chart.register(zoomPlugin)

// Inter is the app's sans (see app.css). chart.js draws on a canvas, so it is
// named here too, and the chart waits for it before drawing.
const FONT_FAMILY = "Inter, system-ui, sans-serif"
const FONT = `11px ${FONT_FAMILY}`

// The space between axis ticks for each time frame: half-hours across three
// hours, every four hours across a day, and days across a week.
const TICK_STEPS = { minute: 30, hour: 4, day: 1 }

const TICK_FORMATS = {
  millisecond: "h:mm:ss.SSS a",
  second: "h:mm:ss a",
  minute: "h:mm a",
  hour: "h:mm a",
  day: "MMM d",
}

// Replaces chart.js's ticks with ones on round times for the time frame, such
// as 9:00 and 9:30 rather than 9:03 and 9:33. Stepping with the Date setters
// keeps them on the wall clock across a daylight-saving change. A zoomed chart
// has no unit set and keeps chart.js's own.
function alignedTicks(scale) {
  const unit = scale.options.time.unit
  const step = TICK_STEPS[unit]
  if (!step) return

  const cursor = new Date(scale.min)
  cursor.setSeconds(0, 0)
  if (unit !== "minute") cursor.setMinutes(0)
  if (unit === "day") cursor.setHours(0)

  const advance = {
    minute: () => cursor.setMinutes(cursor.getMinutes() + 1),
    hour: () => cursor.setHours(cursor.getHours() + 1),
    day: () => cursor.setDate(cursor.getDate() + 1),
  }[unit]

  const position = {
    minute: () => cursor.getMinutes(),
    hour: () => cursor.getHours(),
    day: () => 0,
  }[unit]

  while (cursor.getTime() < scale.min || position() % step !== 0) advance()

  const ticks = []
  while (cursor.getTime() <= scale.max) {
    ticks.push({ value: cursor.getTime() })
    for (let i = 0; i < step; i++) advance()
  }

  scale.ticks = ticks
}

// The page's own tokens, read off the document root so the charts follow the
// light/dark swap.
function palette() {
  const styles = getComputedStyle(document.documentElement)
  const token = (name) => styles.getPropertyValue(name).trim()

  return {
    line: token("--color-chart-1"),
    grid: token("--color-line-subtle"),
    baseline: token("--color-line-strong"),
    tick: token("--color-content-faint"),
    crosshair: token("--color-content-muted"),
    surface: token("--color-surface-raised"),
    border: token("--color-line-default"),
    tooltipTitle: token("--color-content-muted"),
    tooltipBody: token("--color-content-strong"),
    warning: token("--color-warning"),
    warningContent: token("--color-warning-content"),
    alert: token("--color-alert"),
    alertContent: token("--color-alert-content"),
  }
}

// "88%", but "46 °C" and "1612 MB".
function withUnit(value, unit) {
  const rounded = Math.round(value * 10) / 10
  if (!unit) return `${rounded}`
  return unit === "%" ? `${rounded}%` : `${rounded} ${unit}`
}

// The axis drops the C from °C to stay narrow.
function axisLabel(value, unit) {
  if (unit === "%") return `${value}%`
  if (unit === "°C") return `${value}°`
  return `${value}`
}

// Draws the thresholds behind the line: the tint past the warning threshold,
// then a dashed line at each threshold with its name above it, the warning's
// at the left and the alert's at the right. A threshold off the scale isn't
// drawn; the server says so beside the chart instead.
const thresholdsPlugin = {
  id: "healthThresholds",

  beforeDatasetsDraw(chart, _args, options) {
    const { thresholds, colors } = options
    if (!thresholds) return

    const { ctx, chartArea: area, scales } = chart
    const y = scales.y
    const onScale = (value) => typeof value === "number" && value >= y.min && value <= y.max

    ctx.save()

    if (onScale(thresholds.warning)) {
      const edge = y.getPixelForValue(thresholds.warning)
      const [top, bottom] = thresholds.operator === "lte" ? [edge, area.bottom] : [area.top, edge]

      ctx.globalAlpha = 0.07
      ctx.fillStyle = colors.warning
      ctx.fillRect(area.left, top, area.right - area.left, bottom - top)
      ctx.globalAlpha = 1
    }

    const line = (value, stroke, text, label, align) => {
      if (!onScale(value)) return

      const at = Math.round(y.getPixelForValue(value)) + 0.5

      ctx.beginPath()
      ctx.setLineDash([4, 3])
      ctx.lineWidth = 1.25
      ctx.strokeStyle = stroke
      ctx.moveTo(area.left, at)
      ctx.lineTo(area.right, at)
      ctx.stroke()

      ctx.setLineDash([])
      ctx.font = `500 10px ${FONT_FAMILY}`
      ctx.fillStyle = text
      ctx.textAlign = align
      ctx.textBaseline = "alphabetic"
      ctx.fillText(label, align === "left" ? area.left + 6 : area.right - 6, at - 4)
    }

    const unit = options.unit
    line(thresholds.warning, colors.warning, colors.warningContent, `Warning ${withUnit(thresholds.warning, unit)}`, "left")
    line(thresholds.alert, colors.alert, colors.alertContent, `Alert ${withUnit(thresholds.alert, unit)}`, "right")

    ctx.restore()
  },
}

// A vertical line through the reading the tooltip is showing. Drawn before
// the line, so the hovered point sits on top of it.
const crosshairPlugin = {
  id: "healthCrosshair",

  beforeDatasetsDraw(chart, _args, options) {
    const active = chart.tooltip?.getActiveElements() || []
    if (active.length === 0) return

    const { ctx, chartArea: area } = chart
    const x = Math.round(active[0].element.x) + 0.5

    ctx.save()
    ctx.beginPath()
    ctx.lineWidth = 1
    ctx.strokeStyle = options.color
    ctx.moveTo(x, area.top)
    ctx.lineTo(x, area.bottom)
    ctx.stroke()
    ctx.restore()
  },
}

function config({ metrics, thresholds, max, unit, timeUnit, minTime, maxTime, colors }) {
  return {
    type: "line",
    data: {
      datasets: [
        {
          data: metrics,
          parsing: false,
          borderColor: colors.line,
          borderWidth: 2,
          borderCapStyle: "round",
          borderJoinStyle: "round",
          tension: 0,
          spanGaps: true,
          // A sparse history, such as an idle device's one report an hour,
          // reads as dots rather than a line that seems to say more.
          pointRadius: (ctx) => (ctx.dataset.data.length < 40 ? 2 : 0),
          pointBackgroundColor: colors.line,
          pointBorderWidth: 0,
          pointHoverRadius: 4,
          pointHoverBorderWidth: 2,
          pointHoverBackgroundColor: colors.line,
          pointHoverBorderColor: colors.surface,
        },
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      animation: false,
      interaction: { mode: "nearest", axis: "x", intersect: false },
      layout: { padding: { top: 2 } },
      plugins: {
        title: { display: false },
        legend: { display: false },
        healthThresholds: { thresholds, colors, unit },
        healthCrosshair: { color: colors.crosshair },
        tooltip: {
          displayColors: false,
          backgroundColor: colors.surface,
          borderColor: colors.border,
          borderWidth: 1,
          cornerRadius: 4,
          caretSize: 0,
          padding: { x: 10, y: 8 },
          titleColor: colors.tooltipTitle,
          titleFont: { family: FONT_FAMILY, size: 11, weight: "normal" },
          titleMarginBottom: 3,
          bodyColor: colors.tooltipBody,
          bodyFont: { family: FONT_FAMILY, size: 12, weight: "600" },
          callbacks: {
            title: (items) => format(new Date(items[0].parsed.x), "MMM d, h:mm a"),
            label: (item) => withUnit(item.parsed.y, unit),
          },
        },
        zoom: {
          zoom: {
            drag: {
              enabled: true,
              backgroundColor: "rgba(113, 113, 122, 0.12)",
              borderWidth: 0,
            },
            mode: "x",
            // Every chart on the tab follows the one that was zoomed.
            onZoomComplete: ({ chart }) => {
              const { min, max } = chart.scales.x
              window.dispatchEvent(new CustomEvent("chartZoomed", { detail: { min, max } }))
            },
          },
        },
      },
      scales: {
        x: {
          type: "time",
          min: minTime,
          max: maxTime,
          time: {
            unit: timeUnit,
            stepSize: TICK_STEPS[timeUnit],
            displayFormats: TICK_FORMATS,
          },
          afterBuildTicks: alignedTicks,
          grid: { display: false },
          border: { display: true, color: colors.baseline },
          ticks: {
            color: colors.tick,
            font: { family: FONT_FAMILY, size: 11 },
            maxRotation: 0,
            autoSkip: true,
            autoSkipPadding: 16,
            padding: 4,
          },
        },
        y: {
          type: "linear",
          suggestedMin: 0,
          suggestedMax: max,
          // A metric with no natural scale, such as signal strength, gets room
          // around its readings so small wobbles don't fill the chart.
          grace: max === undefined ? "50%" : 0,
          grid: { color: colors.grid, drawTicks: false },
          border: { display: false },
          ticks: {
            color: colors.tick,
            font: { family: FONT_FAMILY, size: 11 },
            maxTicksLimit: 3,
            padding: 8,
            callback: (value) => axisLabel(value, unit),
          },
        },
      },
    },
  }
}

function setTimeFrame(chart, { from, until, unit }) {
  const x = chart.options.scales.x
  x.min = from
  x.max = until

  if (unit) {
    x.time.unit = unit
    x.time.stepSize = TICK_STEPS[unit]
  }
}

export default {
  mounted() {
    const key = this.el.dataset.key
    const thresholds = JSON.parse(this.el.dataset.thresholds || "null")
    const max = this.el.dataset.max ? Number(this.el.dataset.max) : undefined

    const options = {
      metrics: JSON.parse(this.el.dataset.metrics),
      thresholds,
      max,
      unit: this.el.dataset.valueUnit || "",
      timeUnit: this.el.dataset.timeUnit,
      minTime: JSON.parse(this.el.dataset.mintime),
      maxTime: JSON.parse(this.el.dataset.maxtime),
    }

    const build = (chartOptions) =>
      new Chart(this.el, {
        ...config({ ...chartOptions, colors: palette() }),
        plugins: [thresholdsPlugin, crosshairPlugin],
      })

    whenFontsLoaded([FONT], () => {
      if (!this.el.isConnected) return

      this.chart = build(options)
    })

    this.handleEvent("update-charts", (payload) => {
      if (payload.key !== key || !this.chart) return

      setTimeFrame(this.chart, payload)
      this.chart.data.datasets[0].data = payload.data
      this.chart.update()
    })

    this.handleEvent("update-time-frame", (payload) => {
      if (!this.chart) return

      setTimeFrame(this.chart, payload)
      this.chart.update()
    })

    this.handleEvent("add-data-point", (payload) => {
      if (payload.key !== key || !this.chart) return

      setTimeFrame(this.chart, payload)
      this.chart.data.datasets[0].data.push(payload.data)
      this.chart.update()
    })

    // Every colour comes from the theme, so a theme change draws the chart
    // afresh, keeping its readings and the span it shows.
    this.onThemeUpdated = () => {
      if (!this.chart) return

      const data = this.chart.data.datasets[0].data
      const { min, max, time } = this.chart.options.scales.x
      this.chart.destroy()
      this.chart = build({ ...options, metrics: data })

      Object.assign(this.chart.options.scales.x, { min, max })
      Object.assign(this.chart.options.scales.x.time, { unit: time.unit, stepSize: time.stepSize })
      this.chart.update()
    }

    // A zoom shows its span with ticks chart.js picks, rather than the time
    // frame's.
    this.onZoomed = ({ detail }) => {
      if (!this.chart) return

      const x = this.chart.options.scales.x
      x.min = detail.min
      x.max = detail.max
      x.time.unit = false
      x.time.stepSize = undefined
      this.chart.update()
    }

    window.addEventListener("themeUpdated", this.onThemeUpdated)
    window.addEventListener("chartZoomed", this.onZoomed)
  },

  destroyed() {
    window.removeEventListener("themeUpdated", this.onThemeUpdated)
    window.removeEventListener("chartZoomed", this.onZoomed)
    this.chart?.destroy()
  },
}
