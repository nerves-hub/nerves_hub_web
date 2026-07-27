import Chart from "chart.js/auto"
import { format } from "date-fns"

// First letter of each weekday, indexed by `Date#getDay()` (0 = Sunday).
const WEEKDAY_INITIALS = ["S", "M", "T", "W", "T", "F", "S"]

// Formats an hour-of-day (0-23) as a friendly label, e.g. 0 -> "12am",
// 12 -> "midday", 15 -> "3pm".
function formatHour(hour) {
  if (hour === 0) return "12am"
  if (hour === 12) return "midday"
  return `${hour % 12}${hour < 12 ? "am" : "pm"}`
}

// x-axis tick label for the hourly (24 hour) chart: only label ticks every
// 3 hours (12am, 3am, 6am, 9am, midday, 3pm, 6pm, 9pm), hiding any others.
function hourTickLabel(date) {
  const hour = date.getHours()
  return hour % 3 === 0 ? formatHour(hour) : null
}

// x-axis tick label for the 4 week chart: the day-of-week initial, except
// Mondays which also show the date (e.g. "1 Jun") on a second line below the
// initial to anchor each week. Returning an array renders a multi-line label.
function fourWeekTickLabel(date) {
  const initial = WEEKDAY_INITIALS[date.getDay()]
  return date.getDay() === 1 ? [initial, format(date, "d MMM")] : initial
}

// Returns the x-axis tick label function for the given period.
function tickLabelFor(period) {
  switch (period) {
    case "twenty_four_hours":
      return (_value, index, ticks) => hourTickLabel(new Date(ticks[index].value))
    case "four_weeks":
      return (_value, index, ticks) => fourWeekTickLabel(new Date(ticks[index].value))
    // 14 days: a label on every (daily) tick, e.g. "Jun 12".
    default:
      return (_value, index, ticks) => format(new Date(ticks[index].value), "MMM d")
  }
}

// Replaces the x-axis ticks with one at every 3rd hour of the clock (00:00,
// 03:00, ... 21:00) within the scale's range. Stepping via `setHours` keeps the
// ticks aligned to the wall clock across a daylight-saving change.
function buildThreeHourlyTicks(scale) {
  const cursor = new Date(scale.min)
  cursor.setMinutes(0, 0, 0)
  while (cursor.getHours() % 3 !== 0) {
    cursor.setHours(cursor.getHours() + 1)
  }

  const ticks = []
  while (cursor.getTime() <= scale.max) {
    ticks.push({ value: cursor.getTime() })
    cursor.setHours(cursor.getHours() + 3)
  }

  scale.ticks = ticks
}

const valueLabels = {
  id: "valueLabels",
  afterDatasetsDraw(chart, _args, opts) {
    const { ctx } = chart
    const o = {
      font: "11px ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', 'Courier New', monospace",
      color: "#71717a",
      offset: 10,
      formatter: (v) => v,
      display: true,
      ...opts,
    }
    const resolve = (v, c) => (typeof v === "function" ? v(c) : v)

    ctx.save()
    chart.data.datasets.forEach((dataset, di) => {
      const meta = chart.getDatasetMeta(di)
      if (meta.hidden || meta.type !== "bar") return

      meta.data.forEach((bar, i) => {
        const value = dataset.data[i]
        if (value === null || value === undefined) return

        const c = { chart, dataset, datasetIndex: di, dataIndex: i, value }
        if (!resolve(o.display, c)) return

        const { x, y, base } = bar.getProps(["x", "y", "base"], true)
        const horizontal = meta.iScale.axis === "y"
        const text = String(o.formatter(value, c))

        ctx.font = resolve(o.font, c)
        ctx.fillStyle = resolve(o.color, c)

        if (horizontal) {
          ctx.textBaseline = "middle"
          if (x >= base) {
            // grows right
            ctx.textAlign = "left"
            ctx.fillText(text, x + o.offset, y)
          } else {
            // grows left (negative)
            ctx.textAlign = "right"
            ctx.fillText(text, x - o.offset, y)
          }
        } else {
          ctx.textAlign = "center"
          if (y <= base) {
            // grows up
            ctx.textBaseline = "bottom"
            ctx.fillText(text, x, y - o.offset)
          } else {
            // grows down (negative)
            ctx.textBaseline = "top"
            ctx.fillText(text, x, y + o.offset)
          }
        }
      })
    })
    ctx.restore()
  },
}

export default {
  mounted() {
    let metrics = JSON.parse(this.el.dataset.metrics)

    let maxDate = JSON.parse(this.el.dataset.maxdate)
    let minDate = JSON.parse(this.el.dataset.mindate)

    let unit = this.el.dataset.unit
    let period = this.el.dataset.period

    const areaChartDataset = {
      type: "bar",
      data: {
        datasets: [
          {
            radius: 2,
            data: metrics,
            parsing: {
              xAxisKey: "day",
              yAxisKey: "count",
            },
            borderColor: "rgba(99, 102, 241, 0.65)",
            borderWidth: 1,
            borderRadius: 3,
            backgroundColor: function (context) {
              const chart = context.chart
              const { ctx, chartArea } = chart

              // Prevent errors during the initial layout render
              if (!chartArea) {
                return null
              }

              // Define coordinates: (startX, startY, endX, endY)
              // Vertical gradient goes from chart top to chart bottom
              const gradient = ctx.createLinearGradient(
                0,
                chartArea.top,
                0,
                chartArea.bottom,
              )

              gradient.addColorStop(0, "rgba(99, 102, 241, 0.85)")
              gradient.addColorStop(1, "rgba(99, 102, 241, 0.35)")

              return gradient
            },
          },
        ],
      },
      options: {
        layout: {
          padding: { top: 24 }, // room so labels aren't clipped
        },
        plugins: {
          title: {
            display: false,
          },
          legend: {
            display: false,
          },
          tooltip: false,
          valueLabels: {
            // hide the label for empty (zero-filled) intervals
            display: (c) => c.value.count !== 0,
            formatter: (v) => `${v.count}`,
          },
        },
        scales: {
          x: {
            grid: {
              display: false,
              color: null,
            },
            border: {
              display: false,
            },
            type: "time",
            time: {
              unit: unit,
            },
            // For the hourly chart, force a tick at every 3rd hour (12am, 3am,
            // ... 9pm) instead of relying on chart.js's width-based spacing.
            afterBuildTicks: unit === "hour" ? buildThreeHourlyTicks : undefined,
            ticks: {
              source: "auto",
              display: true,
              autoSkip: false,
              callback: tickLabelFor(period),
              font: {
                family:
                  "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', 'Courier New', monospace",
                size: 11,
              },
            },
            min: minDate,
            max: maxDate,
          },
          y: {
            grid: {
              display: false,
              color: null,
            },
            border: {
              display: false,
            },
            ticks: {
              display: false,
            },
            type: "linear",
            suggestedMin: 0,
            suggestedMax: 10,
          },
        },
        responsive: true,
        maintainAspectRatio: false,
      },
      plugins: [valueLabels],
    }

    const chart = new Chart(this.el, areaChartDataset)

    this.el.chart = chart
  },
}
