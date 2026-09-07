import Chart from "chart.js/auto"

// Reads the categorical chart palette off the document root, so the slice
// colours come from the same `--color-chart-*` tokens the HTML legend uses and
// follow the light/dark theme swap.
function palette(slices) {
  const styles = getComputedStyle(document.documentElement)

  return slices.map((slice, index) =>
    styles.getPropertyValue(slice.filter ? `--color-chart-${index + 1}` : "--color-chart-other").trim(),
  )
}

// The card surface, used for the gap drawn between slices so they're separated
// by negative space rather than by a border.
function surfaceColor() {
  return getComputedStyle(document.documentElement).getPropertyValue("--color-surface-raised").trim()
}

export default {
  mounted() {
    const slices = JSON.parse(this.el.dataset.slices)
    const total = slices.reduce((sum, slice) => sum + slice.count, 0)

    this.chart = new Chart(this.el, {
      type: "doughnut",
      data: {
        labels: slices.map((slice) => slice.label),
        datasets: [
          {
            data: slices.map((slice) => slice.count),
            backgroundColor: palette(slices),
            borderColor: surfaceColor(),
            borderWidth: 2,
            hoverOffset: 4,
          },
        ],
      },
      options: {
        cutout: "68%",
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          // Identity is carried by the HTML legend beside the chart, which
          // also lists the counts, so the canvas doesn't repeat it.
          legend: { display: false },
          tooltip: {
            displayColors: false,
            callbacks: {
              label: (context) => {
                const count = context.parsed
                const share = total === 0 ? 0 : Math.round((count / total) * 100)
                return `${count} ${count === 1 ? "device" : "devices"} (${share}%)`
              },
            },
          },
        },
        // Only the slices which map to a device filter are clickable; a folded
        // "Other" slice has no single version to filter on.
        onClick: (_event, elements) => {
          if (!elements.length) return

          const slice = slices[elements[0].index]
          if (!slice.filter) return

          this.pushEvent("view-devices-with-firmware-version", {
            version: slice.filter,
          })
        },
        onHover: (event, elements) => {
          const clickable = elements.length > 0 && slices[elements[0].index].filter
          event.native.target.style.cursor = clickable ? "pointer" : "default"
        },
      },
    })

    this.onThemeUpdated = () => {
      this.chart.data.datasets[0].backgroundColor = palette(slices)
      this.chart.data.datasets[0].borderColor = surfaceColor()
      this.chart.update()
    }

    window.addEventListener("themeUpdated", this.onThemeUpdated)
  },

  destroyed() {
    window.removeEventListener("themeUpdated", this.onThemeUpdated)
    this.chart?.destroy()
  },
}
