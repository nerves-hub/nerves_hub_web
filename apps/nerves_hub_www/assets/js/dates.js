let formatLastCommunication = last_communication => {
  if (last_communication == 'never') {
    return last_communication
  } else {
    const date = new Date(last_communication)
    return date.toLocaleString('en-US', { timeZoneName: 'short' })
  }
}

module.exports = { formatLastCommunication }
