import Chart from "chart.js/auto"
import zoomPlugin from "chartjs-plugin-zoom"
import { format } from "date-fns"

export default {
  mounted() {
    let key = this.el.dataset.key
    let metrics = JSON.parse(this.el.dataset.metrics)

    let max = null
    // let min = JSON.parse(this.el.dataset.min)

    let maxTime = JSON.parse(this.el.dataset.maxtime)
    let minTime = JSON.parse(this.el.dataset.mintime)

    let title = this.el.dataset.title
    let unit = this.el.dataset.unit

    if (this.el.dataset.max != "") {
      max = this.el.dataset.max
    }

    const areaChartDataset = {
      type: "scatter",
      data: {
        datasets: [
          {
            radius: 2,
            data: metrics,
            pointBackgroundColor: "rgb(97, 95, 255)",
            pointBorderColor: "rgb(97, 95, 255)",
            parsing: false,
          },
        ],
      },
      options: {
        plugins: {
          title: {
            // the label is rendered as editable HTML above the chart, so only
            // show the canvas title when one is explicitly provided
            display: !!title,
            align: "start",
            text: title,
            font: {
              size: 16,
              weight: "normal",
            },
            color: null,
            padding: {
              bottom: 14,
            },
          },
          legend: {
            display: false,
          },
          tooltip: {
            displayColors: false,
            callbacks: {
              title: function (context) {
                return format(
                  new Date(context[0].parsed.x),
                  "dd-MM-yyyy : HH:mm:ssaaa",
                )
              },
              label: function (context) {
                return `${context.parsed.y}`
              },
            },
          },
          zoom: {
            zoom: {
              drag: {
                enabled: true,
              },
              mode: "x",
              onZoomComplete: function (chartRef) {
                const { min, max } = chartRef.chart.scales.x

                const event = new CustomEvent("chartZoomed", {
                  detail: { min: min, max: max },
                })

                window.dispatchEvent(event)

                chart.options.scales.x.time.unit = false

                chart.update()
              },
            },
          },
        },
        scales: {
          x: {
            grid: {
              color: null,
            },
            type: "time",
            time: {
              unit: unit,
              displayFormats: {
                millisecond: "HH:mm:ss.SSSaaa",
                second: "HH:mm:ssaaa",
                minute: "HH:mmaaa",
                hour: "HH:mmaaa",
              },
            },
            ticks: {
              source: "auto",
              display: true,
              autoSkip: false,
            },
            min: minTime,
            max: maxTime,
          },
          y: {
            grid: {
              color: null,
            },
            type: "linear",
            suggestedMin: 0,
            suggestedMax: max,
          },
        },
        responsive: true,
        maintainAspectRatio: false,
      },
    }

    setThemeColors(areaChartDataset)

    Chart.register(zoomPlugin)

    const chart = new Chart(this.el, areaChartDataset)
    this.el.chart = chart

    this.handleEvent("update-charts", function (payload) {
      if (payload.key == key) {
        chart.options.scales.x.time.unit = payload.unit
        chart.options.scales.x.min = payload.from
        chart.options.scales.x.max = payload.until
        chart.options.scales.x.suggestedMin = payload.from
        chart.options.scales.x.suggestedMax = payload.until

        chart.data.datasets[0].data = payload.data

        chart.update()
      }
    })

    this.handleEvent("update-time-frame", function (payload) {
      chart.options.scales.x.min = payload.from
      chart.options.scales.x.max = payload.until
      chart.options.scales.x.suggestedMin = payload.from
      chart.options.scales.x.suggestedMax = payload.until

      chart.update()
    })

    this.handleEvent("add-data-point", function (payload) {
      if (payload.key == key) {
        let data = chart.data.datasets[0].data
        data.push(payload.data)

        chart.options.scales.x.min = payload.from
        chart.options.scales.x.max = payload.until
        chart.options.scales.x.suggestedMin = payload.from
        chart.options.scales.x.suggestedMax = payload.until

        chart.data.datasets[0].data = data

        chart.update()
      }
    })

    window.addEventListener("themeUpdated", function (payload) {
      setThemeColors(chart)
      chart.update()
    })

    window.addEventListener("chartZoomed", function (payload) {
      chart.options.scales.x.min = payload.detail.min
      chart.options.scales.x.max = payload.detail.max
      chart.update()
    })

    function setThemeColors(chart) {
      let theme = document.documentElement.getAttribute("data-theme")

      if (theme == "dark") {
        chart.options.plugins.title.color = "rgba(212, 212, 216)"
        chart.options.scales.x.grid.color = "rgba(63, 63, 70)"
        chart.options.scales.y.grid.color = "rgba(63, 63, 70)"
      } else if (theme == "light") {
        chart.options.plugins.title.color = "rgba(9, 9, 11)"
        chart.options.scales.x.grid.color = "rgba(218, 218, 218)"
        chart.options.scales.y.grid.color = "rgba(218, 218, 218)"
      }
    }
  },
}
