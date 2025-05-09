export default {
  mounted() {
    this.updated()
  },
  updated() {
    let dt = new Date(this.el.textContent.trim())

    function p(s) {
      return s < 10 ? "0" + s : s
    }

    function p3(s) {
      let result
      if (s < 10) {
        result = "00" + s
      } else if (s < 100) {
        result = "0" + s
      } else {
        result = s
      }
      return result
    }

    const tzAbbr = () => {
      var dateObject = new Date(),
        dateString = dateObject + "",
        tzAbbr =
          // Works for the majority of modern browsers
          dateString.match(/\(([^\)]+)\)$/) ||
          // IE outputs date strings in a different format:
          dateString.match(/([A-Z]+) [\d]{4}$/)

      if (tzAbbr) {
        // Old Firefox uses the long timezone name (e.g., "Central
        // Daylight Time" instead of "CDT")
        tzAbbr = tzAbbr[1].match(/[A-Z]/g).join("")
      }

      // Return a GMT offset for browsers that don't include the
      // user's zone abbreviation (e.g. "GMT-0500".)
      // First seen on: http://stackoverflow.com/a/12496442
      if (!tzAbbr && /(GMT\W*\d{4})/.test(dateString)) {
        return /(GMT\W*\d{4})/.exec(dateString)[1]
      }

      return tzAbbr
    }

    const day = dt.getDate()
    const month = dt.getMonth() + 1
    const year = dt.getFullYear()
    const hour = dt.getHours()
    const minute = dt.getMinutes()
    const seconds = dt.getSeconds()
    const milliseconds = dt.getMilliseconds()
    const timezone = tzAbbr()

    const time = `${p(hour)}:${p(minute)}:${p(seconds)}.${p3(milliseconds)}`

    this.el.textContent = `${year}-${p(month)}-${p(day)} ${time} ${timezone}`
  }
}
