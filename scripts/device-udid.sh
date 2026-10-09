#!/bin/bash
# Prints the UDID of the paired iPhone to install on.
#
# Usage: device-udid.sh [NAME_OR_UDID]
#
# With an argument, picks the paired iPhone whose name, UDID or CoreDevice identifier
# matches it. Without one, picks a paired iPhone this Mac can reach now, preferring a
# cable over Wi-Fi.
set -euo pipefail

want="${1:-}"
json="$(mktemp)"
trap 'rm -f "$json"' EXIT

xcrun devicectl list devices --quiet --json-output "$json" > /dev/null

udid="$(
  jq -r --arg want "$want" '
    [ .result.devices[]
      | select(.hardwareProperties.deviceType == "iPhone")
      | select(.connectionProperties.pairingState == "paired")
      | select(if $want == "" then .connectionProperties.transportType != null
               else (.deviceProperties.name == $want or .hardwareProperties.udid == $want
                     or .identifier == $want) end) ]
    | sort_by(if .connectionProperties.transportType == "wired" then 0 else 1 end)
    | .[0].hardwareProperties.udid // empty' "$json"
)"

if [[ -z "$udid" ]]; then
  if [[ -n "$want" ]]; then
    echo "error: no paired iPhone named or with UDID '$want'." >&2
  else
    echo "error: no paired iPhone is reachable. Unlock it and connect it by cable or Wi-Fi." >&2
  fi
  echo "List devices with: xcrun devicectl list devices" >&2
  exit 1
fi

echo "$udid"
