const dates = require('./dates')

describe('formatDateTime', () => {
  test('formats ISO 8601 dates', () => {
    let date = new Date()

    date.setMilliseconds(0)
    expect(new Date(dates.formatDateTime(date.toISOString())).getTime()).toBe(
      date.getTime()
    )
  })

  test('preserves "never" value', () => {
    expect(dates.formatDateTime('never')).toBe('never')
  })

  test('handles white space around "never" value', () => {
    expect(dates.formatDateTime(' never  ')).toBe('never')
  })
})
