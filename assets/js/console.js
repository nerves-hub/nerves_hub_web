/* eslint no-console: ["error", { allow: ["log"] }] */

import { Socket } from 'phoenix';
import { Terminal } from 'xterm';

let socket = new Socket('/socket', { params: { token: window.userToken } });

const xtermjsTheme = {
  foreground: '#FFFAF4',
  background: '#0E1019',
  selectionBackground: '#48B9C7',
  black: '#232323',
  brightBlack: '#444444',
  red: '#D82036',
  brightRed: '#FF2740',
  green: '#8CE10B',
  brightGreen: '#ABE15B',
  yellow: '#FFB900',
  brightYellow: '#FFD242',
  blue: '#007AD8',
  brightBlue: '#0092FF',
  magenta: '#6D43A6',
  brightMagenta: '#9A5FEB',
  cyan: '#00D8EB',
  brightCyan: '#67FFF0',
  white: '#FFFFFF',
  brightWhite: '#FFFFFF'
};

// Try loading scrollback from local storage. If not, use 1000 (which is xterm.js default)
let scrollback = 1000;
try {
  let stored_scrollback = parseInt(localStorage.getItem('scrollback'));
  if (Number.isSafeInteger(stored_scrollback)) {
    scrollback = stored_scrollback;
  }
} catch (e) {}

var term = new Terminal({
  rows: 25,
  cols: 120,
  cursorBlink: true,
  cursorStyle: 'bar',
  macOptionIsMeta: true,
  fontFamily: '"Roboto Mono", monospace',
  theme: xtermjsTheme,
  scrollback: scrollback,
})

var device_id = document.getElementById('device_id').value;
var product_id = document.getElementById('product_id').value;

socket.connect();

term.open(document.getElementById('terminal'));
term.focus();

let channel = socket.channel('user_console', { device_id, product_id });

channel
  .join()
  .receive('ok', () => {
    console.log('JOINED');
    // This will be the same for everyone, the first time it should be used
    // and there after it will be ignored as a noop by erlang
    channel.push('window_size', { height: term.rows, width: term.cols });
  })
  .receive('error', () => {
    console.log('ERROR');
  });

// Stream all events straight to the device
term.onData(data => {
  channel.push('dn', { data })
});

// Write data from device to console
channel.on('up', payload => {
  term.write(payload.data)
});

// Set new size on device when window changes
window.addEventListener('resize', () => {
  term.scrollToBottom();
});

channel.onClose(() => {
  console.log('CLOSED');
  term.blur();
  term.setOption('cursorBlink', false);
  term.write('DISCONNECTED');
});
