#!/usr/bin/env bash
# The emulated assistant, started by a wake ping. It uses only `al`: reads what is waiting,
# and when a call is on, stays for it and answers every voice message at once.
# Env: AL (the al command, with its --key-file and --server options).
set -euo pipefail

reply() {
  $AL send "E2E reply $1: $(jq -r .text_message.text <<<"$2" | cut -d' ' -f1-4)" >/dev/null
}

in_call=false
while read -r event; do
  case $(jq -r .type <<<"$event") in
    call_started) in_call=true ;;
    call_ended) in_call=false ;;
    text_message) reply 0 "$event" ;;
  esac
done < <($AL read)

$in_call || exit 0
echo "call on"
n=0
$AL call | while read -r event; do
  if [[ $(jq -r .type <<<"$event") == text_message ]]; then reply $((++n)) "$event"; fi
done
echo "al call exited"
