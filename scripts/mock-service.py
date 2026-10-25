#!/usr/bin/env python3
"""A stand-in for the Assistant Link service that answers what the app calls at launch.

Usage: mock-service.py [PORT]   (default 8765, listens on 127.0.0.1)

Serves canned data that mirrors `Assistant.samples`, and accepts any credential.
"""
import json
import re
import sys
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def iso(delta):
    moment = datetime.now(timezone.utc) + delta
    return moment.isoformat(timespec="milliseconds").replace("+00:00", "Z")


def link(link_id, label, status, last_active_at):
    return {
        "id": link_id,
        "label": label,
        "status": status,
        "last_active_at": last_active_at,
    }


def assistants():
    return [
        {
            "id": "01a11a4e-0771-7baf-8a8b-2f8f3f86e219",
            "name": "Hermes",
            "avatar": "avatar-3",
            "status": "online",
            "links": [
                link("01a11a4e-0a6a-7edf-996d-7e8f06fc11ed", "laptop", "online", iso(timedelta())),
                link(
                    "01a11a4e-42ee-7ebf-b82d-d195d2252d57",
                    "cloud",
                    "offline",
                    iso(timedelta(hours=-2)),
                ),
                link("01a11a5f-1c00-7a1b-9c2d-3e4f5a6b7c8d", None, "not_paired", None),
            ],
        },
        {
            "id": "01a11a4f-0000-7000-8000-000000000001",
            "name": "Grok Bot",
            "avatar": "avatar-6",
            "status": "offline",
            "links": [],
        },
        {
            "id": "01a11a4f-0000-7000-8000-000000000002",
            "name": "Muse",
            "avatar": "avatar-1",
            "status": "offline",
            "links": [link("01a0f5c2-8000-7000-8000-000000000003", None, "not_paired", None)],
        },
    ]


def route(method, path):
    if method == "POST" and path == "/api/v1/accounts":
        return 201, {"account_id": "01a11a4e-0000-7000-8000-0000000000aa", "credential": "mock"}
    if method == "GET" and path == "/api/v1/assistants":
        return 200, {"assistants": assistants()}
    if method == "POST" and re.fullmatch(r"/api/v1/assistants/[^/]+/links", path):
        return 201, {"link": link("01a11a60-0000-7000-8000-000000000004", None, "not_paired", None)}
    if method == "POST" and re.fullmatch(r"/api/v1/links/[^/]+/pairing_code", path):
        return 201, {
            "code": "K7QM-2XPA",
            "expires_at": iso(timedelta(minutes=10)),
            "pairing_text": "Pair with Assistant Link using the code K7QM-2XPA.",
        }
    return 404, {"error": {"code": "not_found", "message": "Not found."}}


class Handler(BaseHTTPRequestHandler):
    def respond(self):
        self.rfile.read(int(self.headers.get("Content-Length") or 0))
        status, body = route(self.command, self.path.split("?")[0])
        payload = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    do_GET = do_POST = do_DELETE = respond


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
