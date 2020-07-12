/* eslint no-console: ["error", { allow: ["log"] }] */

import { Terminal } from 'xterm'
// import { FitAddon } from 'xterm-addon-fit';

export default class IEx {
  start(socket) {
    var term = new Terminal({
      cursorBlink: true,
      cursorStyle: 'bar',
      macOptionIsMeta: true
    })
    var restart_button = document.getElementById('restart_button')
    // const fitAddon = new FitAddon()
    // term.loadAddon(fitAddon)

    var device_id = document.getElementById('device_id').value

    socket.connect()

    term.open(document.getElementById('terminal'))
    // fitAddon.fit()

    term.focus()

    let channel = socket.channel('user_console', { device_id })

    channel
      .join()
      .receive('ok', () => {
        console.log('JOINED')
        // Push CTL-L to refresh form line
        channel.push('dn', { data: '\f' })
      })
      .receive('error', () => {
        console.log('ERROR')
      })

    // Stream all events straight to the device
    term.onData(data => {
      channel.push('dn', { data })
    })

    // Write data from device to console
    channel.on('up', payload => {
      term.write(payload.data)
    })

    channel.onClose(() => {
      console.log('CLOSED')
      term.blur()
      term.setOption('cursorBlink', false)
      term.write('DISCONNECTED')
    })

    restart_button.addEventListener('click', () => {
      var check = confirm('Are you sure you want to restart the IEx process?')
      if (check == true) {
        channel.push('restart', {})
      }
    })
  }
}
