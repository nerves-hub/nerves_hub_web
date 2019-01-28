import { Presence, Socket } from 'phoenix'

let socket = new Socket('/socket', { params: { token: window.userToken } })

socket.connect()

let channel = socket.channel(`devices:${window.orgId}`, {})
let presences = {}

let updateStatuses = presences => {
  document.querySelectorAll('.device').forEach(d => {
    const {
      [d.dataset.deviceId]: { status } = { status: 'offline' }
    } = presences
    d.innerHTML = status
  })
}

channel.on('presence_state', state => {
  presences = Presence.syncState(presences, state)
  updateStatuses(presences)
})

channel.on('presence_diff', diff => {
  presences = Presence.syncDiff(presences, diff)
  updateStatuses(presences)
})

channel
  .join()
  .receive('ok', () => {})
  .receive('error', () => {})

export default socket
