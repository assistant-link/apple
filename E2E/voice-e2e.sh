#!/usr/bin/env bash
# Voice call end to end: a real AppModel and VoiceCall (fake speech engines) against a live
# service, with an `al`-only assistant woken through a webhook.
# Env: SERVER, AL, NTFY, VOICE_E2E_CACHE.
set -euo pipefail
cd "$(dirname "$0")"

export SERVER=${SERVER:-https://assistant-link.fly.dev}
export AL_SERVER=$SERVER
NTFY=${NTFY:-https://ntfy.sh}
AL=${AL:-al}
tmp=$(mktemp -d)
export E2E_DIR=$PWD
credential=

cleanup() {
  kill $(jobs -p) 2>/dev/null || true
  [[ -z $credential ]] || api DELETE account >/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

api() {
  curl -fsS -X "$1" -H "Authorization: Bearer $credential" -H 'Content-Type: application/json' \
    -d "${3:-{\}}" "$SERVER/api/v1/$2"
}

swift build >&2

credential=$(api POST accounts | jq -r .credential)
assistant=$(api POST assistants '{"name":"E2E voice test","avatar":"avatar-1"}' | jq -r .assistant.id)
link=$(api POST "assistants/$assistant/links" | jq -r .link.id)
code=$(api POST "links/$link/pairing_code" | jq -r .code)

export AL="$AL --key-file $tmp/link.key"
$AL pair "$code" >/dev/null

topic=al-e2e-$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')
python3 wake_receiver.py "$NTFY" "$topic" "$tmp" &
for _ in $(seq 100); do [[ -e $tmp/subscribed ]] && break; sleep 0.1; done
[[ -e $tmp/subscribed ]] || { echo "FAIL: not subscribed to $NTFY"; exit 1; }
$AL webhook set "$NTFY/$topic" >/dev/null

status=0
E2E_CREDENTIAL=$credential E2E_ASSISTANT_ID=$assistant "$(swift build --show-bin-path)/VoiceE2E" ||
  status=1

for _ in $(seq 40); do [[ -s $tmp/assistant.exit ]] && break; sleep 0.5; done
wakes=$(wc -l 2>/dev/null <"$tmp/wakes.log" || echo 0)
[[ $wakes -eq 1 ]] || { echo "FAIL: $wakes wake pings, expected 1"; status=1; }
[[ $(cat "$tmp/assistant.exit" 2>/dev/null) == 0 ]] ||
  { echo "FAIL: the assistant did not exit 0"; status=1; }
grep -q 'al call exited' "$tmp/assistant.log" 2>/dev/null ||
  { echo "FAIL: al call did not exit after call_ended"; status=1; }

if [[ $status -eq 0 ]]; then echo PASS; else echo FAIL; cat "$tmp/assistant.log" 2>/dev/null; fi
exit $status
