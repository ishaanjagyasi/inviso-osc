/**
 * OSC -> WebSocket relay for Inviso.
 *
 * The browser cannot receive raw OSC over UDP, so this listens on a UDP port
 * and rebroadcasts every message it decodes as JSON to any connected browser.
 *
 * The UDP port is controlled from the app's OSC panel: browsers send
 * {type: 'setPort', port} and the relay rebinds. Status is broadcast back as
 * {type: 'status', port, listening, error} so the panel can show what happened.
 */

const osc = require('osc');
const WebSocket = require('ws');

const DEFAULT_OSC_PORT = 9000;
const WS_PORT = 8081;

let udp = null;
let state = { port: DEFAULT_OSC_PORT, listening: false, error: null };

const wss = new WebSocket.Server({ port: WS_PORT });

function broadcast(payload) {
  const json = JSON.stringify(payload);

  wss.clients.forEach((client) => {
    if (client.readyState === WebSocket.OPEN) client.send(json);
  });
}

function status() {
  return {
    type: 'status',
    port: state.port,
    listening: state.listening,
    error: state.error,
  };
}

function listen(port) {
  if (udp) {
    try {
      udp.close();
    } catch (e) {
      /* Never opened, or already closed. */
    }
    udp = null;
  }

  state = { port: port, listening: false, error: null };

  udp = new osc.UDPPort({
    localAddress: '0.0.0.0',
    localPort: port,
    // Deliver args as plain values rather than {type, value} wrappers.
    metadata: false,
  });

  udp.on('ready', () => {
    state.listening = true;
    state.error = null;
    console.log('Listening for OSC over UDP on port ' + port);
    broadcast(status());
  });

  // Fires for standalone messages and for each message inside a bundle.
  udp.on('message', (oscMessage) => {
    broadcast({ address: oscMessage.address, args: oscMessage.args });
  });

  udp.on('error', (err) => {
    state.listening = false;
    state.error = err.message;
    console.error('OSC error on port ' + port + ': ' + err.message);
    broadcast(status());
  });

  udp.open();
}

wss.on('listening', () => {
  console.log('WebSocket server listening on ws://localhost:' + WS_PORT);
});

wss.on('connection', (client) => {
  client.send(JSON.stringify(status()));

  client.on('message', (data) => {
    let message;

    try {
      message = JSON.parse(data);
    } catch (e) {
      return;
    }

    if (!message || message.type !== 'setPort') return;

    const port = Number(message.port);

    if (!Number.isInteger(port) || port < 1024 || port > 65535) return;

    /* Rebind on a new port, or retry the current one after a failure. */
    if (port !== state.port || !state.listening) listen(port);
  });
});

listen(DEFAULT_OSC_PORT);
