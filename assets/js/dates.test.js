const dates = require('./dates')
const moment = require('moment')

describe('formatDateTime', () => {
  test('formats ISO 8601 dates', () => {
    let date = new Date()
    let testDate = moment
      .utc(date)
      .local()
      .format('MMM Do, YYYY [at] h:mma')

    expect(dates.formatDateTime(date.toISOString())).toBe(testDate)
  })

  test('preserves "never" value', () => {
    expect(dates.formatDateTime('never')).toBe('never')
  })

  test('handles white space around "never" value', () => {
    expect(dates.formatDateTime(' never  ')).toBe('never')
  })
})
