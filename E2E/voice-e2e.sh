#!/usr/bin/env bash
# Voice call end to end: a real AppModel and VoiceCall (fake speech engines) against a live
# service, with an `al`-only assistant woken through a webhook. Env: SERVER, AL, VOICE_E2E_CACHE.
set -euo pipefail
cd "$(dirname "$0")"

export SERVER=${SERVER:-https://assistant-link.fly.dev}
export AL_SERVER=$SERVER
AL=${AL:-al}
tmp=$(mktemp -d)
export E2E_DIR=$PWD
credential=
pids=()

cleanup() {
  kill "${pids[@]}" 2>/dev/null || true
  [[ -z $credential ]] || api DELETE account >/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

api() {
  curl -fsS -X "$1" -H "Authorization: Bearer $credential" -H 'Content-Type: application/json' \
    -d "${3:-{\}}" "$SERVER/api/v1/$2"
}

credential=$(api POST accounts | jq -r .credential)
assistant=$(api POST assistants '{"name":"E2E voice test","avatar":"avatar-1"}' | jq -r .assistant.id)
link=$(api POST "assistants/$assistant/links" | jq -r .link.id)
code=$(api POST "links/$link/pairing_code" | jq -r .code)

export AL="$AL --key-file $tmp/link.key"
$AL pair "$code" >/dev/null

token=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
./wake_receiver.py "Bearer $token" "$tmp" &
pids+=($!)
while [[ ! -s $tmp/port ]]; do sleep 0.1; done
cloudflared tunnel --url "http://localhost:$(<"$tmp/port")" >"$tmp/tunnel.log" 2>&1 &
pids+=($!)
until url=$(grep -om1 'https://[a-z0-9-]*\.trycloudflare\.com' "$tmp/tunnel.log"); do sleep 0.5; done
AL_WEBHOOK_HEADER="Authorization: Bearer $token" $AL webhook set "$url" >/dev/null
sleep 5 # the new tunnel hostname needs a moment to resolve

swift build -Xlinker --allow-shlib-undefined >&2
status=0
E2E_CREDENTIAL=$credential E2E_ASSISTANT_ID=$assistant "$(swift build --show-bin-path)/VoiceE2E" ||
  status=1

for _ in $(seq 40); do [[ -s $tmp/assistant.exit ]] && break; sleep 0.5; done
wakes=$(wc -l <"$tmp/wakes.log" 2>/dev/null || echo 0)
[[ $wakes -eq 1 ]] || { echo "FAIL: $wakes wake pings, expected 1"; status=1; }
[[ $(cat "$tmp/assistant.exit" 2>/dev/null) == 0 ]] || { echo "FAIL: the assistant did not exit 0"; status=1; }
grep -q 'al call exited' "$tmp/assistant.log" 2>/dev/null ||
  { echo "FAIL: al call did not exit after call_ended"; status=1; }

if [[ $status -eq 0 ]]; then echo PASS; else echo FAIL; cat "$tmp/assistant.log" 2>/dev/null; fi
exit $status
