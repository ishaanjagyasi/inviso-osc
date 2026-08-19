# Inviso with OSC control

A cross-platform tool for designing interactive virtual soundscapes, extended with external control of the listener head over OSC.

Inviso lets you build 3D soundscapes in the browser: place sound objects, draw sound zones, animate them along trajectories, and move a listener head through the scene to hear the result binaurally or as 3rd-order ambisonics. An ACM UIST paper about Inviso, including a video figure, can be found [here](https://dl.acm.org/citation.cfm?doid=3126594.3126644).

This fork adds an OSC input path so the listener head can be driven from external software, alongside the existing keyboard and mouse controls.

For the original project documentation — build scripts, project structure, and ambisonics setup — see [`inviso_original_readme.md`](inviso_original_readme.md).

## Credits

Inviso is developed at the University of Michigan.

Project leader, primary developer: Anıl Çamcı [<acamci@umich.edu> • http://anilcamci.com]<br/>
Developers: [2025] Yun Ma <yunma@umich.edu>, [2024-2025] Michael Cella <mjcella@umich.edu>, [2019-2021] Tanya Lai <tanyalai@umich.edu>, Julia Xu <juliawxu@umich.edu>, [2016-2017] Kristine Lee <khlee2@uic.edu>, Cody J. Roberts <codyroberts@protonmail.com>, Angus Forbes <angus@ucsc.edu>

The OSC control described below was added on top of that work.

## What was added

Browsers cannot receive raw OSC, because a web page is not allowed to open a listening socket. The feature is therefore split in two:

* **`osc-bridge/`** — a small Node relay that listens for OSC over UDP and forwards each message as JSON over a WebSocket on port 8081.
* **`src/js/app/managers/osc.js`** — a WebSocket client in the app that applies incoming messages to the listener head.

Incoming messages are buffered and the latest value is applied once per animation frame, so a fast sender cannot flood the render loop. Updates reuse the same code path as the W/A/S/D keys, which means OSC is additive: keyboard and mouse control keep working, and OSC yields to an active mouse drag or a running trajectory exactly as the keys do.

A panel in the top bar toggles OSC on and off, sets the UDP port, and reports relay status. Both settings persist between sessions.

## Setup

Requires Node 16 — the project builds with webpack 2, which fails on Node 17 and later.

```
./setup.sh      # macOS and Linux
.\setup.ps1     # Windows
```

The script works from wherever the repository was cloned. It selects Node 16 through nvm, installs dependencies for both the app and the relay, rebuilds `node-sass` if no prebuilt binary is available for the platform, starts the relay, and opens the app at `localhost:8080`.

To clone and set up in one step on a new machine, use `bootstrap.sh` (or `bootstrap.ps1`). Re-running it updates an existing clone.

On Apple Silicon, `node-sass` has no prebuilt binary and is compiled from source, which requires the Xcode command line tools:

```
xcode-select --install
```

## Usage

1. Click **OSC** in the top bar to enable it.
2. Set the UDP port. The relay rebinds immediately — no restart required.
3. Confirm the status line reads *Listening on UDP \<port\>* in green.
4. Send OSC to that port on `127.0.0.1`.

## Message schema

```
/inviso/listener/position     x y z             floats, normalized -1..1
/inviso/listener/orientation  yaw pitch roll    floats in radians
```

**Position** — all three arguments are normalized to the range -1..1:

| Argument | Axis | Negative to positive | Scene range |
| --- | --- | --- | --- |
| `x` | left/right | left to right | ±5000 units |
| `y` | height | down to up | ±300 units |
| `z` | forward/back | forward to back | ±5000 units |

Forward is negative `z`, following the convention already used throughout the app. Only `y` is clamped; values outside -1..1 on `x` and `z` will place the head off the visible grid. At the default zoom level roughly ±0.25 is visible on screen.

Height is not visible in the default aerial view. Tilt the camera into altitude view to see it.

**Orientation** — `yaw` is applied in radians and is unbounded. `pitch` and `roll` are accepted and ignored, as the listener head tracks orientation solely through its yaw everywhere else in the app.

## Testing

A test script is included that exercises position, height, yaw, and a continuous orbit:

```
pip3 install python-osc
python3 osc-bridge/test_osc.py          # port 7777
python3 osc-bridge/test_osc.py 9000     # or any other port
```

Set the same port in the OSC panel before running it.

## Troubleshooting

**Status reads "Relay not running"** — the relay is not up. Re-run `setup.sh`, which starts it.

**Status is green but nothing moves** — the port in the app and the port in your sender do not match.

**The head jumps off screen** — position values are normalized. Keep them within roughly ±0.2 while working at the default zoom.
