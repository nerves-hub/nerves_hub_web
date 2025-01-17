import Chart from "chart.js/auto"

export default {
  dataset() {
    return JSON.parse(this.el.dataset.metrics)
  },
  unit() {
    return JSON.parse(this.el.dataset.unit)
  },
  mounted() {
    let metrics = JSON.parse(this.el.dataset.metrics)
    let type = JSON.parse(this.el.dataset.type)
    let max = JSON.parse(this.el.dataset.max)
    let min = JSON.parse(this.el.dataset.min)
    let title = JSON.parse(this.el.dataset.title)

    const ctx = this.el
    var data = []
    for (let i = 0; i < metrics.length; i++) {
      data.push(metrics[i])
    }

    const areaChartDataset = {
      type: "line",
      data: {
        datasets: [
          {
            backgroundColor: "rgba(99, 102, 241)",
            fill: {
              target: "start",
              above: "rgba(99, 102, 241, 0.29)",
              below: "rgba(99, 102, 241, 0.29)"
            },
            radius: 2,
            data: this.dataset()
          }
        ]
      },
      options: {
        plugins: {
          title: {
            display: true,
            align: "start",
            text: title,
            font: {
              size: 16,
              weight: "normal"
            },
            color: "rgba(212, 212, 216)",
            padding: {
              bottom: 14
            }
          },
          legend: {
            display: false
          }
        },
        scales: {
          x: {
            grid: {
              color: "rgba(63, 63, 70)"
            },
            type: "time",
            time: {
              unit: this.unit(),
              displayFormats: {
                millisecond: "HH:mm:ss.SSS",
                second: "HH:mm:ss",
                minute: "HH:mm",
                hour: "HH:mm"
              }
            },
            ticks: {
              display: true,
              autoSkip: false
            }
          },
          y: {
            offset: true,
            grid: {
              color: "rgba(63 63 70)"
            },
            type: "linear",
            min: 0
            // max: max
          }
        },
        responsive: true,
        maintainAspectRatio: false
      }
    }

    const chart = new Chart(ctx, areaChartDataset)
    this.el.chart = chart

    this.handleEvent("update-charts", function(payload) {
      if (payload.type == type) {
        chart.data.datasets[0].data = payload.data
        chart.update()
      }
    })

    this.handleEvent("update-time-unit", function(payload) {
      chart.options.scales.x.time.unit = payload.unit
      chart.update()
    })
  }
}
