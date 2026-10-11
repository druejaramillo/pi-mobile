#!/usr/bin/env node
// Test-owned external executable; never starts or connects to an installed Herdr server.
import { createConnection } from 'node:net';
import { createInterface } from 'node:readline';
const args = process.argv.slice(2);
if (args[0] !== '--session' || args[1] !== 'test-only' || !process.env.PI_MOBILE_TEST_HERDR_SOCKET) process.exit(2);
if (args[2] === 'remote-api-bridge') {
  const socket = createConnection(process.env.PI_MOBILE_TEST_HERDR_SOCKET);
  socket.on('error', () => process.exit(3));
  process.stdin.pipe(socket).pipe(process.stdout);
  socket.on('close', () => process.exit());
} else if (args.slice(2, 4).join(' ') === 'terminal session' && args[5] === 'term_live') {
  if (args[4] === 'control' && !args.includes('--takeover')) {
    process.stderr.write('fixture private diagnostic: control is held elsewhere\n');
    process.exit(4);
  }
  let width = Number(args[args.indexOf('--cols') + 1]);
  let height = Number(args[args.indexOf('--rows') + 1]);
  function frame(bytes) {
    process.stdout.write(JSON.stringify({ type: 'terminal.frame', encoding: 'ansi', bytes, width, height }) + '\n');
  }
  frame(Buffer.from('Existing terminal\r\n').toString('base64'));
  createInterface({ input: process.stdin, terminal: false }).on('line', (line) => {
    const command = JSON.parse(line);
    if (command.type === 'terminal.input') frame(command.bytes);
    else if (command.type === 'terminal.resize') {
      width = command.cols; height = command.rows;
      frame(Buffer.from('Resized').toString('base64'));
    } else if (command.type === 'terminal.release') process.exit();
  }).on('close', () => process.exit());
} else process.exit(2);
