import { format } from "date-fns"

// The x-axis shared by the time-bucketed bar charts on the Insights page, so
// the connection history and the update history read as one chart drawn twice
// rather than two charts that happen to sit near each other.

export const MONO_FONT_FAMILY =
  "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', 'Courier New', monospace"

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
export function tickLabelFor(period) {
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
export function buildThreeHourlyTicks(scale) {
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

// The recessive time axis both charts draw: no grid, no border, monospace tick
// labels, and bounds pinned to the window the server bucketed so the bars sit
// flush against both edges.
export function timeAxis({ unit, period, min, max }) {
  return {
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
        family: MONO_FONT_FAMILY,
        size: 11,
      },
    },
    min,
    max,
  }
}
