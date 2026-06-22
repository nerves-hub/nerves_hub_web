import Chart from "chart.js/auto"

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
            ticks: {
              source: "auto",
              display: true,
              autoSkip: false,
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
