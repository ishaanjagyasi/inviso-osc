#!/usr/bin/env python3
"""
Sends test OSC to Inviso so you can check the listener head responds.

    pip3 install python-osc
    python3 test_osc.py            # port 7777
    python3 test_osc.py 9000       # or any other port

Set the same port in Inviso's OSC panel first, and make sure it reads
"Listening on UDP <port>" in green.

Positions are normalized -1..1 across the floor. Values are kept small
because anything past about 0.25 leaves the default camera view.
"""

import math
import sys
import time

from pythonosc.udp_client import SimpleUDPClient

HOST = "127.0.0.1"
POSITION = "/inviso/listener/position"
ORIENTATION = "/inviso/listener/orientation"


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 7777
    client = SimpleUDPClient(HOST, port)

    print("Sending OSC to {}:{}".format(HOST, port))
    print("Watch the blue head in Inviso. Ctrl-C to stop.\n")

    def move(x, y, z, label):
        print("  {:<28} {: .2f} {: .2f} {: .2f}".format(label, x, y, z))
        client.send_message(POSITION, [float(x), float(y), float(z)])
        time.sleep(1.2)

    def turn(yaw, label):
        print("  {:<28} {: .0f} degrees".format(label, math.degrees(yaw)))
        client.send_message(ORIENTATION, [float(yaw), 0.0, 0.0])
        time.sleep(1.2)

    print("1. Position")
    move(0.0, 0.0, 0.0, "centre")
    move(0.15, 0.0, 0.0, "right")
    move(-0.15, 0.0, 0.0, "left")
    move(0.0, 0.0, -0.15, "forward")
    move(0.0, 0.0, 0.15, "back")
    move(0.0, 0.0, 0.0, "centre")

    print("\n2. Height (switch to Altitude view to see this)")
    move(0.0, 1.0, 0.0, "up")
    move(0.0, -1.0, 0.0, "down")
    move(0.0, 0.0, 0.0, "centre")

    print("\n3. Orientation")
    for degrees in (0, 90, 180, 270, 360):
        turn(math.radians(degrees), "yaw")

    print("\n4. Smooth orbit (10 seconds)")
    print("   If you have sound objects placed, this is where you should")
    print("   hear the binaural image rotate around you.")

    steps = 600
    for i in range(steps):
        angle = i / steps * 2 * math.pi
        client.send_message(
            POSITION, [0.15 * math.cos(angle), 0.0, 0.15 * math.sin(angle)]
        )
        # Face along the direction of travel.
        client.send_message(ORIENTATION, [-angle, 0.0, 0.0])
        time.sleep(1 / 60)

    client.send_message(POSITION, [0.0, 0.0, 0.0])
    client.send_message(ORIENTATION, [0.0, 0.0, 0.0])
    print("\nDone. Head returned to centre.")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nStopped.")
