"""Plays an agent host: listens to an ntfy topic that receives the service's wake pings and
starts assistant.sh on a wake. Usage: wake_receiver.py <ntfy url> <topic> <folder>.
Writes <folder>/subscribed, wakes.log, assistant.log and, when the assistant exits, assistant.exit."""

import json
import os
import signal
import subprocess
import sys
import threading
import urllib.request
from pathlib import Path

ntfy, topic, folder = sys.argv[1], sys.argv[2], Path(sys.argv[3])
assistant = None


def stop(*_):
    if assistant and assistant.poll() is None:
        os.killpg(assistant.pid, signal.SIGTERM)
    sys.exit()


def watch(process):
    folder.joinpath("assistant.exit").write_text(f"{process.wait()}\n")


signal.signal(signal.SIGTERM, stop)
with urllib.request.urlopen(f"{ntfy}/{topic}/json") as stream:
    for line in stream:
        event = json.loads(line)
        if event["event"] == "open":
            folder.joinpath("subscribed").touch()
        if event["event"] != "message":
            continue
        with folder.joinpath("wakes.log").open("a") as log:
            log.write(event["message"] + "\n")
        if json.loads(event["message"]).get("type") == "wake" and not (
            assistant and assistant.poll() is None
        ):
            log = folder.joinpath("assistant.log").open("w")
            assistant = subprocess.Popen(
                [Path(__file__).with_name("assistant.sh")],
                stdout=log,
                stderr=subprocess.STDOUT,
                start_new_session=True,
            )
            threading.Thread(target=watch, args=(assistant,), daemon=True).start()
