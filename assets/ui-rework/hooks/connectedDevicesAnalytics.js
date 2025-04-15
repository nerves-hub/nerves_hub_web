import Chart from "chart.js/auto"

export default {
  mounted() {
    let unit = this.el.dataset.unit

    let label_singual = this.el.dataset.labelSingual
    let label_plural = this.el.dataset.labelPlural

    let dataset = JSON.parse(this.el.dataset.metrics)

    const ctx = this.el

    var data = []
    for (let i = 0; i < dataset.length; i++) {
      data.push({
        x: dataset[i].timestamp,
        y: dataset[i].count
      })
    }

    var gradient = ctx.getContext("2d").createLinearGradient(0, 0, 0, 400)
    gradient.addColorStop(0, "rgba(99, 102, 241, 1)")
    gradient.addColorStop(1, "rgba(99, 102, 241, 0)")

    const barChartDataset = {
      type: "bar",
      data: {
        datasets: [
          {
            backgroundColor: gradient,
            hoverBackgroundColor: "#7f9cf5",
            barPercentage: 0.75,
            minBarLength: 2,
            data: data
          }
        ]
      },
      options: {
        plugins: {
          title: {
            display: false
          },
          legend: {
            display: false,
            labels: {
              display: false
            }
          },
          tooltip: {
            callbacks: {
              title: function(context) {
                date = new Date(context[0].parsed.x)
                return date.toLocaleTimeString("en-NZ")
              },
              label: function(context) {
                if (context.raw.y === 1) {
                  unit = label_singual
                } else {
                  unit = label_plural
                }
                return " " + context.formattedValue + " " + unit
              }
            }
          }
        },
        scales: {
          x: {
            display: false,
            // grid: {
            //   display: false,
            //   drawOnChartArea: false,
            //   drawTicks: false
            // },
            type: "time",
            time: {
              unit: unit,
              displayFormats: {
                millisecond: "HH:mm:ss.SSS",
                second: "HH:mm:ss",
                minute: "HH:mm",
                hour: "HH:mm"
              }
            },
            ticks: {
              display: false
            }
          },
          y: {
            offset: false,
            grid: {
              display: false
            },
            type: "linear",
            min: 0,
            // max: max
            ticks: {
              display: false
            }
          }
        },
        responsive: true,
        maintainAspectRatio: false,
        layout: {
          autoPadding: false,
          padding: {
            top: 0,
            right: 10,
            bottom: 0,
            left: 5
          }
        }
      }
    }

    const chart = new Chart(ctx, barChartDataset)
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
