const moment = require('moment')

const formatDateTime = datetime => {
  /*
    Safari wants strict iso8601 format "YYYY-MM-DDTHH:MM:SSZ",
    but elixir to_string default supplies as "YYYY-MM-DD HH:MM:SSZ".
    So this attempts to transform the dates if needed
  */
  datetime = datetime
    .trim()
    .split(' ')
    .join('T')

  if (datetime === 'never' || datetime === '') {
    return datetime
  } else {
    return moment
      .utc(datetime)
      .local()
      .format('MMM Do, YYYY [at] h:mma')
  }
}

const formatDate = datetime => {
  /*
    Safari wants strict iso8601 format "YYYY-MM-DDTHH:MM:SSZ",
    but elixir to_string default supplies as "YYYY-MM-DD HH:MM:SSZ".
    So this attempts to transform the dates if needed
  */
  datetime = datetime
    .trim()
    .split(' ')
    .join('T')

  if (datetime === 'never' || datetime === '') {
    return datetime
  } else {
    return moment
      .utc(datetime)
      .local()
      .format('MMM Do, YYYY')
  }
}

module.exports = { formatDateTime, formatDate }
