#!/usr/bin/env python3
"""Receives the service's wake pings and starts assistant.sh, as an agent host would.
Usage: wake_receiver.py <authorization> <folder>; writes <folder>/port, wakes.log, assistant.log
and, when the assistant exits, assistant.exit."""

import json
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

authorization, folder = sys.argv[1], Path(sys.argv[2])
assistant = None


def watch(process):
    folder.joinpath("assistant.exit").write_text(f"{process.wait()}\n")


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        global assistant
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if self.headers.get("Authorization") != authorization:
            return self.send_response(401), self.end_headers()
        with folder.joinpath("wakes.log").open("a") as log:
            log.write(body.decode() + "\n")
        if json.loads(body).get("type") == "wake" and not (assistant and assistant.poll() is None):
            log = folder.joinpath("assistant.log").open("w")
            assistant = subprocess.Popen(
                [Path(__file__).with_name("assistant.sh")], stdout=log, stderr=subprocess.STDOUT
            )
            threading.Thread(target=watch, args=(assistant,)).start()
        self.send_response(204)
        self.end_headers()

    def log_message(self, *args):
        pass


server = HTTPServer(("127.0.0.1", 0), Handler)
folder.joinpath("port").write_text(str(server.server_port))
server.serve_forever()
