import Chart from "chart.js/auto"
import { MONO_FONT_FAMILY, timeAxis } from "../helpers/timeAxis.js"

// Successes and failures are a status pair, not a categorical one, so they wear
// the page's own `--color-success` / `--color-danger` tokens — the two the Fleet
// Health bar already uses — read off the document root so they follow the
// light/dark swap rather than being flipped automatically.
//
// Red and green is the pair colour-vision deficiency handles worst, so identity
// never rests on colour alone here: the HTML legend beside the chart names both
// series and carries their totals, the failed series is always the upper
// segment, and the tooltip names whichever segment is hovered.
function seriesColors() {
  const styles = getComputedStyle(document.documentElement)

  return {
    succeeded: styles.getPropertyValue("--color-success").trim(),
    failed: styles.getPropertyValue("--color-danger").trim(),
    surface: styles.getPropertyValue("--color-surface-raised").trim(),
  }
}

// One dataset per outcome, both reading the same buckets. The bottom segment
// carries a 2px top border in the card's own colour, which is the gap between
// the two fills — and is invisible, rather than a stray cap, on a bucket that
// had no failures at all.
function datasets(buckets, colors) {
  return [
    {
      label: "Successful",
      data: buckets,
      parsing: { xAxisKey: "day", yAxisKey: "succeeded" },
      backgroundColor: colors.succeeded,
      borderColor: colors.surface,
      borderWidth: { top: 2, right: 0, bottom: 0, left: 0 },
      borderRadius: 3,
      borderSkipped: false,
    },
    {
      label: "Failed",
      data: buckets,
      parsing: { xAxisKey: "day", yAxisKey: "failed" },
      backgroundColor: colors.failed,
      borderWidth: 0,
      borderRadius: 3,
      borderSkipped: false,
    },
  ]
}

export default {
  mounted() {
    const buckets = JSON.parse(this.el.dataset.buckets)
    const maxDate = JSON.parse(this.el.dataset.maxdate)
    const minDate = JSON.parse(this.el.dataset.mindate)

    const unit = this.el.dataset.unit
    const period = this.el.dataset.period

    const colors = seriesColors()

    this.chart = new Chart(this.el, {
      type: "bar",
      data: { datasets: datasets(buckets, colors) },
      options: {
        plugins: {
          title: { display: false },
          // Identity is carried by the HTML legend beside the chart, which also
          // lists the totals, so the canvas doesn't repeat it.
          legend: { display: false },
          tooltip: {
            mode: "index",
            intersect: false,
            bodyFont: { family: MONO_FONT_FAMILY, size: 11 },
            titleFont: { family: MONO_FONT_FAMILY, size: 11 },
            callbacks: {
              label: (context) =>
                ` ${context.dataset.label}: ${context.parsed.y}`,
            },
          },
        },
        scales: {
          x: {
            ...timeAxis({ unit: unit, period: period, min: minDate, max: maxDate }),
            stacked: true,
          },
          y: {
            grid: { display: false, color: null },
            border: { display: false },
            ticks: { display: false },
            type: "linear",
            stacked: true,
            suggestedMin: 0,
            suggestedMax: 10,
          },
        },
        responsive: true,
        maintainAspectRatio: false,
      },
    })

    this.onThemeUpdated = () => {
      const updated = seriesColors()

      this.chart.data.datasets.forEach((dataset, index) => {
        const next = datasets(buckets, updated)[index]
        dataset.backgroundColor = next.backgroundColor
        dataset.borderColor = next.borderColor
      })

      this.chart.update()
    }

    window.addEventListener("themeUpdated", this.onThemeUpdated)
  },

  destroyed() {
    window.removeEventListener("themeUpdated", this.onThemeUpdated)
    this.chart?.destroy()
  },
}
