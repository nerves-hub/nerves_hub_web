export default {
  mounted() {
    this.updateTimer = null
    this.updated()
  },
  updated(element) {
    let hook = arguments.length > 0 ? element : this

    if (hook.updateTimer) {
      clearTimeout(hook.updateTimer)
    }

    const timeAgo = new TimeAgo("en-US")

    let dtString = hook.el.dateTime
    let dt = new Date(dtString)

    const formattedDate = timeAgo.format(dt, "round-minute")

    hook.el.textContent = formattedDate

    // https://www.npmjs.com/package/javascript-time-ago#update-interval
    // set update interval to 10sec
    let interval = 10000

    hook.updateTimer = setTimeout(hook.updated, interval, hook)
  }
}
