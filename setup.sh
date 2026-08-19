#!/usr/bin/env bash
#
# Sets up and runs Inviso with OSC control on macOS and Linux.
# Works from wherever the repo was cloned. Run: ./setup.sh
#
# The app needs Node 16: it builds with webpack 2, which breaks on Node 17+
# because OpenSSL 3 removed the md4 hash it uses for module ids.

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NODE_VERSION=16

cd "$REPO_DIR" || exit 1

info() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$1"; }
fail() { printf '\033[1;31m==>\033[0m %s\n' "$1" >&2; exit 1; }

# --- Node 16 -----------------------------------------------------------------

load_nvm() {
  for candidate in \
    "${NVM_DIR:-$HOME/.nvm}/nvm.sh" \
    /opt/homebrew/opt/nvm/nvm.sh \
    /usr/local/opt/nvm/nvm.sh
  do
    if [ -s "$candidate" ]; then
      export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
      mkdir -p "$NVM_DIR"
      # shellcheck disable=SC1090
      . "$candidate"
      return 0
    fi
  done

  return 1
}

current_major() {
  command -v node >/dev/null 2>&1 || return 1
  node -v 2>/dev/null | sed 's/^v\([0-9]*\).*/\1/'
}

if [ "$(current_major)" = "$NODE_VERSION" ]; then
  info "Node $(node -v) already active."
else
  if load_nvm; then
    info "Found nvm, selecting Node $NODE_VERSION..."
  else
    warn "Node $NODE_VERSION is required and nvm was not found."
    printf 'Install nvm now from https://github.com/nvm-sh/nvm? [y/N] '
    read -r reply

    case "$reply" in
      [yY]*)
        curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash \
          || fail "nvm install failed."
        load_nvm || fail "nvm installed but could not be loaded; open a new terminal and re-run."
        ;;
      *)
        fail "Install Node $NODE_VERSION manually, then re-run this script."
        ;;
    esac
  fi

  nvm install "$NODE_VERSION" >/dev/null 2>&1
  nvm use "$NODE_VERSION" >/dev/null 2>&1 || fail "Could not activate Node $NODE_VERSION."
  info "Using Node $(node -v)."
fi

# --- Dependencies ------------------------------------------------------------

# node_modules is committed upstream, so its presence proves nothing about
# whether it matches package.json. Always let npm reconcile the two; it is
# quick when there is nothing to do.
# --legacy-peer-deps because sass-loader 6 declares a peer of node-sass 4
# while the project pins node-sass 8. The conflict predates this work and is
# harmless: nothing imports .scss through webpack, so sass-loader never runs.
info "Checking app dependencies..."
npm install --legacy-peer-deps || fail "npm install failed in $REPO_DIR."

if [ ! -d osc-bridge/node_modules ]; then
  info "Installing relay dependencies..."
  (cd osc-bridge && npm install) || fail "npm install failed in osc-bridge."
else
  info "Relay dependencies already installed."
fi

# node-sass ships no prebuilt binary for some platforms (notably Apple Silicon),
# so compile it locally when the prebuilt one will not load.
if ! node -e "require('node-sass')" >/dev/null 2>&1; then
  info "Building node-sass for this platform..."
  npm rebuild node-sass --build-from-source \
    || fail "node-sass build failed. On Linux install build-essential and python3, then re-run."
fi

# --- Run ---------------------------------------------------------------------

cleanup() {
  if [ -n "${RELAY_PID:-}" ] && kill -0 "$RELAY_PID" 2>/dev/null; then
    kill "$RELAY_PID" 2>/dev/null
  fi
}
trap cleanup EXIT INT TERM

# lsof cannot always see listening sockets it does not own, so ask Node to try
# an actual connection instead.
port_in_use() {
  node -e "
    const net = require('net');
    const socket = net.connect($1, '127.0.0.1');
    socket.on('connect', () => { socket.end(); process.exit(0); });
    socket.on('error', () => process.exit(1));
    setTimeout(() => process.exit(1), 1000);
  " >/dev/null 2>&1
}

if port_in_use 8081; then
  info "Relay already running on port 8081, leaving it alone."
else
  info "Starting OSC relay..."
  (cd osc-bridge && node index.js) &
  RELAY_PID=$!
fi

info "Starting Inviso at http://localhost:8080"
info "Click OSC in the top bar to enable it and set your UDP port."
npm run dev
