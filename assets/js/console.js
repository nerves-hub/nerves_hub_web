/* eslint no-console: ["error", { allow: ["log"] }] */

import { Socket } from 'phoenix';
import { Terminal } from 'xterm';
import { FitAddon } from 'xterm-addon-fit';

let socket = new Socket('/socket', { params: { token: window.userToken } })

const xtermjsTheme = {
  foreground: '#FFFAF4',
  background: '#0E1019',
  selectionBackground: '#48B9C7',
  black: '#232323',
  brightBlack: '#444444',
  red: '#FFFAF4',
  brightRed: '#FF2740',
  green: '#8CE10B',
  brightGreen: '#ABE15B',
  yellow: '#FFB900',
  brightYellow: '#FFD242',
  blue: '#008DF8',
  brightBlue: '#0092FF',
  magenta: '#6D43A6',
  brightMagenta: '#9A5FEB',
  cyan: '#00D8EB',
  brightCyan: '#67FFF0',
  white: '#FFFFFF',
  brightWhite: '#FFFFFF'
};

var term = new Terminal({
  cursorBlink: true,
  cursorStyle: 'bar',
  macOptionIsMeta: true,
  fontFamily: '"Roboto Mono", monospace',
  theme: xtermjsTheme,
})
const fitAddon = new FitAddon();
term.loadAddon(fitAddon);

var device_id = document.getElementById('device_id').value
var product_id = document.getElementById('product_id').value

socket.connect()

term.open(document.getElementById('terminal'))
fitAddon.fit()

term.focus()

let channel = socket.channel('user_console', { device_id, product_id })

channel
  .join()
  .receive('ok', () => {
    console.log('JOINED')
    // Push CTL-L to refresh form line
    channel.push('dn', { data: '\f' })
    channel.push('window_size', { height: term.rows, width: term.cols })
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

// Update meta fields for page
channel.on('meta_update', payload => {
  var deets = document.getElementById('status-deets')
  var inner
  if (payload.status === 'updating') {
    inner = `
      <div class="progress console-progress">
        <div class="progress-bar" role="progressbar" style="width: ${payload.fwup_progress}%">
          ${payload.fwup_progress}%
        </div>
      </div>
      `
  } else {
    inner = `
    <span>${payload.status}</span>
    <span class="ml-1">
      <img alt="${payload.status}" class="table-icon ${payload.status}" />
    </span>
    `
  }
  deets.innerHTML = inner

  if ('last_communication' in payload) {
    document.getElementById('last_communication').value =
      payload.last_communication
  }
})

// Set new size on device when window changes
window.addEventListener('resize', () => {
  fitAddon.fit()
  term.scrollToBottom()
  channel.push('window_size', { height: term.rows, width: term.cols })
})

channel.onClose(() => {
  console.log('CLOSED')
  term.blur()
  term.setOption('cursorBlink', false)
  term.write('DISCONNECTED')
})
