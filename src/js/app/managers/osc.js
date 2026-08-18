/**
 * Listener-head control over OSC, received as JSON from the osc-bridge relay.
 *
 * Incoming messages are buffered and the latest value for each property is
 * applied once per animation frame from Main.updateDummyHead(), which then
 * runs its usual WASD branch to mirror the head onto the helpers and refresh
 * the binaural output via setListenerPosition().
 *
 * Schema:
 *   /inviso/listener/position     x y z     floats, normalized -1..1
 *   /inviso/listener/orientation  yaw pitch roll  floats in radians
 */

const WS_URL = 'ws://localhost:8081';
const RECONNECT_DELAY = 3000;
const PORT_STORAGE_KEY = 'inviso-osc-port';
const ENABLED_STORAGE_KEY = 'inviso-osc-enabled';
const DEFAULT_PORT = 9000;

/**
 * Position args are normalized -1..1 and scaled onto the scene here. X and Z
 * span the ground grid (Config.grid.size of 10000, so ±5000 from the centre);
 * Y spans the altitude range the mouse drag already clamps to in
 * HeadObject.move().
 */
const FLOOR_HALF_EXTENT = 5000;
const ALTITUDE_LIMIT = 300;

export default class OSC {
  constructor(main) {
    this.main = main;
    this.socket = null;
    this.enabled = window.localStorage.getItem(ENABLED_STORAGE_KEY) === 'true';

    /* Relay state, as last reported by the bridge. */
    this.connected = false;
    this.listening = false;
    this.error = null;

    /* Latest value received since the last frame, or null if nothing new. */
    this.pendingPosition = null;
    this.pendingYaw = null;

    this.port = readStoredPort();

    this.setupUI();
    this.connect();
  }

  setupUI() {
    this.label = document.getElementById('oscMode');
    this.panel = document.getElementById('osc-panel');
    this.portInput = document.getElementById('osc-port');
    this.statusText = document.getElementById('osc-status');

    if (this.portInput) this.portInput.value = this.port;

    if (this.label) {
      this.label.addEventListener('click', () => this.setEnabled(!this.enabled));
    }

    if (this.portInput) {
      this.portInput.addEventListener('change', () => this.applyPortFromInput());
      this.portInput.addEventListener('keydown', (event) => {
        if (event.keyCode === 13) this.portInput.blur();
      });
    }

    this.render();
  }

  setEnabled(enabled) {
    this.enabled = enabled;
    window.localStorage.setItem(ENABLED_STORAGE_KEY, String(enabled));

    /* Drop anything buffered so switching back on cannot apply a stale pose. */
    this.pendingPosition = null;
    this.pendingYaw = null;

    this.render();
  }

  applyPortFromInput() {
    const port = Number(this.portInput.value);

    if (!isFinite(port) || port % 1 !== 0 || port < 1024 || port > 65535) {
      this.portInput.value = this.port;
      return;
    }

    this.port = port;
    window.localStorage.setItem(PORT_STORAGE_KEY, String(port));

    this.sendPort();
    this.render();
  }

  sendPort() {
    if (!this.socket || this.socket.readyState !== WebSocket.OPEN) return;

    this.socket.send(JSON.stringify({ type: 'setPort', port: this.port }));
  }

  connect() {
    this.socket = new WebSocket(WS_URL);

    this.socket.onopen = () => {
      this.connected = true;
      this.sendPort();
      this.render();
    };

    this.socket.onmessage = (event) => this.onMessage(event);

    this.socket.onclose = () => {
      this.socket = null;
      this.connected = false;
      this.listening = false;
      this.render();
      setTimeout(() => this.connect(), RECONNECT_DELAY);
    };

    /* The relay simply may not be running; onclose handles the retry. */
    this.socket.onerror = () => {};
  }

  onMessage(event) {
    let message;

    try {
      message = JSON.parse(event.data);
    } catch (e) {
      return;
    }

    if (!message) return;

    if (message.type === 'status') {
      this.listening = !!message.listening;
      this.error = message.error || null;
      this.render();
      return;
    }

    if (!this.enabled) return;

    const args = message.args || [];

    if (message.address === '/inviso/listener/position') {
      const x = toNumber(args[0]);
      const y = toNumber(args[1]);
      const z = toNumber(args[2]);

      if (isFinite(x) && isFinite(y) && isFinite(z)) {
        this.pendingPosition = { x: x, y: y, z: z };
      }
    } else if (message.address === '/inviso/listener/orientation') {
      /**
       * Only yaw is applied: the head model tracks orientation solely through
       * rotation.y everywhere else in the app. Pitch and roll are accepted and
       * ignored.
       */
      const yaw = toNumber(args[0]);

      if (isFinite(yaw)) {
        this.pendingYaw = yaw;
      }
    }
  }

  render() {
    if (this.label) {
      this.label.innerHTML = this.enabled ? 'OSC: ' + this.port : 'OSC: Off';
      this.label.classList.toggle('active', this.enabled);
    }

    if (this.panel) {
      this.panel.style.display = this.enabled ? 'block' : 'none';
    }

    if (this.statusText) {
      this.statusText.innerHTML = this.statusMessage();
      this.statusText.className = this.listening ? 'osc-ok' : 'osc-warn';
    }
  }

  statusMessage() {
    if (!this.connected) return 'Relay not running';
    if (this.error) return 'Port ' + this.port + ': ' + this.error;
    if (!this.listening) return 'Connecting&hellip;';

    return 'Listening on UDP ' + this.port;
  }

  /**
   * Applies at most one update per frame so a fast OSC sender cannot flood the
   * render loop. Called from Main.updateDummyHead() before its branches run.
   */
  update() {
    const main = this.main;

    if (!this.enabled || !main.head) return;
    if (this.pendingPosition === null && this.pendingYaw === null) return;

    /**
     * Hands control back to the head model, exactly as a WASD keydown does, so
     * the update below lands in the same branch of updateDummyHead().
     */
    main.isAllowMouseDrag = false;

    if (this.pendingPosition !== null) {
      const p = this.pendingPosition;

      main.head.position.set(
        p.x * FLOOR_HALF_EXTENT,
        Math.max(Math.min(p.y * ALTITUDE_LIMIT, ALTITUDE_LIMIT), -ALTITUDE_LIMIT),
        p.z * FLOOR_HALF_EXTENT,
      );

      /**
       * The WASD branch only nudges the axis helper by the frame's delta, so it
       * has to be resynced here the way the mouse-drag branch does.
       */
      main.axisHelper.position.copy(main.head.position);

      this.pendingPosition = null;
    }

    if (this.pendingYaw !== null) {
      main.head.rotation.y = this.pendingYaw;
      main.axisHelper.rotation.y = this.pendingYaw;

      this.pendingYaw = null;
    }
  }
}

function readStoredPort() {
  const stored = Number(window.localStorage.getItem(PORT_STORAGE_KEY));

  if (isFinite(stored) && stored >= 1024 && stored <= 65535) return stored;

  return DEFAULT_PORT;
}

function toNumber(arg) {
  /* osc.js sends plain values with metadata off, {type, value} with it on. */
  return Number(arg !== null && typeof arg === 'object' ? arg.value : arg);
}
