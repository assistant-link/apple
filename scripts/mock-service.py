#!/usr/bin/env python3
"""A stand-in for the Assistant Link service that answers what the app calls.

Listens on 127.0.0.1:$PORT (default 8765) and accepts any credential. It keeps its
state in memory; `POST /__reset` restores the seed data.

Seed data: Hermes (online, with about 70 events), Atlas (offline, paired Link, a few
events), Muse (only an unpaired Link) and Grok Bot (no Links, no events).

Scenarios, chosen by the text of a message posted to `/api/v1/assistants/:id/messages`:
  - "slow ...": the answer comes after 6 seconds.
  - "fail ...": the answer is 503 and nothing is stored.
"""
import json
import os
import re
import threading
import time
import uuid
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

HERMES = "01a11a4e-0771-7baf-8a8b-2f8f3f86e219"
ATLAS = "01a11a4f-0000-7000-8000-000000000005"
GROK_BOT = "01a11a4f-0000-7000-8000-000000000001"
MUSE = "01a11a4f-0000-7000-8000-000000000002"
LAPTOP = "01a11a4e-0a6a-7edf-996d-7e8f06fc11ed"
ATLAS_LINK = "01a11a4e-9999-7edf-996d-7e8f06fc11ee"

MAX_TEXT_LENGTH = 4000
SLOW_SECONDS = 6

LOCK = threading.Lock()
STATE = {}
LAST_ID = [0, 0]


def stamp(moment):
    return moment.isoformat(timespec="milliseconds").replace("+00:00", "Z")


def iso(delta):
    return stamp(datetime.now(timezone.utc) + delta)


def event_id(moment=None):
    """A UUIDv7-like id: it sorts by time, then by the order of creation."""
    millis = int((moment or datetime.now(timezone.utc)).timestamp() * 1000)
    if millis == LAST_ID[0]:
        LAST_ID[1] += 1
    else:
        LAST_ID[:] = [millis, 0]
    time_part = f"{millis:012x}"
    tail = f"{uuid.uuid4().int & ((1 << 60) - 1):015x}"
    return f"{time_part[:8]}-{time_part[8:]}-7{LAST_ID[1]:03x}-8{tail[:3]}-{tail[3:]}"


def link(link_id, label, status, last_active_at):
    return {
        "id": link_id,
        "label": label,
        "status": status,
        "last_active_at": last_active_at,
    }


def make_event(assistant_id, sender, minutes_ago, text=None, **extra):
    moment = datetime.now(timezone.utc) - timedelta(minutes=minutes_ago)
    event = {
        "id": event_id(moment),
        "assistant_id": assistant_id,
        "type": "text_message",
        "sender": sender,
        "link_id": None,
        "idempotency_key": None,
        "created_at": stamp(moment),
        "deleted": text is None,
    }
    if text is not None:
        event["text_message"] = {"text": text}
    if sender == "user":
        event["idempotency_key"] = event_id(moment)
        event["delivery_status"] = "delivered"
    event.update(extra)
    return event


PROMPTS = [
    "Remind me to call David tomorrow",
    "What is on my calendar this week?",
    "Summarize the notes from the planning meeting",
    "Draft a reply to the landlord about the lease",
    "How long is the drive to the airport?",
    "Add oat milk to the shopping list",
    "Find a quiet cafe near the office",
    "Translate this sentence into Spanish: see you on Friday",
]
REPLIES = [
    "Done. I will remind you at 9:00.",
    "You have three meetings: Monday 10:00, Wednesday 14:00 and Friday 9:30.",
    "The team agreed on the launch date and split the open tasks between two people.",
    "Here is a draft. It keeps the tone friendly and asks for the repairs to be scheduled.",
    "About 35 minutes without traffic.",
    "Added to the shopping list.",
    "Two options within walking distance: Fika on Pine Street and Northside Coffee.",
    "Nos vemos el viernes.",
]


def hermes_events():
    events = []
    total = 71
    for index in range(total):
        minutes_ago = (total - 1 - index) * 95 + 2
        if index == 0:
            moment = datetime.now(timezone.utc) - timedelta(minutes=minutes_ago + 5)
            events.append(
                {
                    "id": event_id(moment),
                    "assistant_id": HERMES,
                    "type": "link_created",
                    "sender": "system",
                    "link_id": LAPTOP,
                    "idempotency_key": None,
                    "created_at": stamp(moment),
                    "deleted": False,
                }
            )
            continue
        pair = (index - 1) // 2
        if index % 2 == 1:
            text = None if index == 21 else PROMPTS[pair % len(PROMPTS)]
            events.append(make_event(HERMES, "user", minutes_ago, text))
        else:
            text = None if index == 34 else REPLIES[pair % len(REPLIES)]
            events.append(make_event(HERMES, "assistant", minutes_ago, text, link_id=LAPTOP))
    return events


def atlas_events():
    return [
        make_event(ATLAS, "user", 600, "Is the backup finished?"),
        make_event(ATLAS, "assistant", 598, "Yes, it finished at 02:14.", link_id=ATLAS_LINK),
        make_event(ATLAS, "user", 300, "Check it again at noon"),
    ]


def seed():
    return {
        "assistants": [
            {
                "id": HERMES,
                "name": "Hermes",
                "avatar": "avatar-3",
                "links": [
                    link(LAPTOP, "laptop", "online", iso(timedelta())),
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
                "id": ATLAS,
                "name": "Atlas",
                "avatar": "avatar-5",
                "links": [link(ATLAS_LINK, "server", "offline", iso(timedelta(hours=-5)))],
            },
            {"id": GROK_BOT, "name": "Grok Bot", "avatar": "avatar-6", "links": []},
            {
                "id": MUSE,
                "name": "Muse",
                "avatar": "avatar-1",
                "links": [link("01a0f5c2-8000-7000-8000-000000000003", None, "not_paired", None)],
            },
        ],
        "events": {
            HERMES: hermes_events(),
            ATLAS: atlas_events(),
            GROK_BOT: [],
            MUSE: [],
        },
    }


def assistant_json(assistant):
    events = STATE["events"][assistant["id"]]
    online = any(entry["status"] == "online" for entry in assistant["links"])
    return dict(
        assistant,
        status="online" if online else "offline",
        latest_event=events[-1] if events else None,
    )


def error(status, code, message):
    return status, {"error": {"code": code, "message": message}}


def list_events(assistant_id, query):
    if assistant_id not in STATE["events"]:
        return error(404, "not_found", "Not found.")
    events = STATE["events"][assistant_id]
    limit = 50
    if "limit" in query:
        value = query["limit"][0]
        if not re.fullmatch(r"[0-9]+", value) or not 1 <= int(value) <= 100:
            return error(422, "invalid_params", "The parameters are not valid.")
        limit = int(value)
    end = len(events)
    if "before" in query:
        ids = [event["id"] for event in events]
        if query["before"][0] not in ids:
            return error(422, "invalid_params", "The parameters are not valid.")
        end = ids.index(query["before"][0])
    start = max(0, end - limit)
    return 200, {"events": events[start:end], "has_more": start > 0}


def create_message(assistant_id, body):
    assistant = next((a for a in STATE["assistants"] if a["id"] == assistant_id), None)
    if assistant is None:
        return error(404, "not_found", "Not found.")
    text = body.get("text")
    key = body.get("idempotency_key")
    events = STATE["events"][assistant_id]
    stored = next((e for e in events if key and e["idempotency_key"] == key), None)
    if stored is not None:
        if stored.get("text_message", {}).get("text") != text:
            return error(
                409, "idempotency_key_conflict", "This idempotency key was used for another message."
            )
        return 200, {"message": stored}
    if not isinstance(text, str) or not isinstance(key, str) or not key:
        return error(422, "invalid_params", "The parameters are not valid.")
    if not text.strip():
        return error(422, "text_empty", "The text must not be empty or only whitespace.")
    if len(text) > MAX_TEXT_LENGTH:
        return error(422, "text_too_long", "The text must have at most 4000 Unicode code points.")
    if all(entry["status"] == "not_paired" for entry in assistant["links"]):
        return error(422, "no_paired_link", "This Assistant has no paired Assistant Link.")
    if text.startswith("fail"):
        return error(503, "service_unavailable", "The service is unavailable.")
    event = make_event(assistant_id, "user", 0, text, idempotency_key=key, delivery_status="sent")
    events.append(event)
    return 201, {"message": event}


def route(method, path, query, body):
    if method == "POST" and path == "/__reset":
        STATE.clear()
        STATE.update(seed())
        return 200, {}
    if method == "POST" and path == "/api/v1/accounts":
        return 201, {"account_id": "01a11a4e-0000-7000-8000-0000000000aa", "credential": "mock"}
    if method == "GET" and path == "/api/v1/assistants":
        return 200, {"assistants": [assistant_json(a) for a in STATE["assistants"]]}
    match = re.fullmatch(r"/api/v1/assistants/([^/]+)/events", path)
    if method == "GET" and match:
        return list_events(match.group(1), query)
    match = re.fullmatch(r"/api/v1/assistants/([^/]+)/messages", path)
    if method == "POST" and match:
        return create_message(match.group(1), body)
    if method == "POST" and re.fullmatch(r"/api/v1/assistants/[^/]+/links", path):
        return 201, {"link": link("01a11a60-0000-7000-8000-000000000004", None, "not_paired", None)}
    if method == "POST" and re.fullmatch(r"/api/v1/links/[^/]+/pairing_code", path):
        return 201, {
            "code": "K7QM-2XPA",
            "expires_at": iso(timedelta(minutes=10)),
            "pairing_text": "Pair with Assistant Link using the code K7QM-2XPA.",
        }
    # /api/v1/connect deliberately 404s so the app skips live updates.
    return error(404, "not_found", "Not found.")


class Handler(BaseHTTPRequestHandler):
    def respond(self):
        raw = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        try:
            body = json.loads(raw) if raw else {}
        except ValueError:
            body = {}
        if not isinstance(body, dict):
            body = {}
        url = urlsplit(self.path)
        with LOCK:
            status, result = route(self.command, url.path, parse_qs(url.query), body)
        text = body.get("text")
        if status == 201 and isinstance(text, str) and text.startswith("slow"):
            time.sleep(SLOW_SECONDS)
        payload = json.dumps(result).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    do_GET = do_POST = do_DELETE = respond

    def log_message(self, format, *args):
        pass


if __name__ == "__main__":
    STATE.update(seed())
    ThreadingHTTPServer(("127.0.0.1", int(os.environ.get("PORT", "8765"))), Handler).serve_forever()
