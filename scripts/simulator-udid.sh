#!/bin/bash
# Prints the UDID of the iOS Simulator device to build, test and run on.
#
# Usage: simulator-udid.sh [NAME_OR_UDID]
#
# With an argument, picks the available device whose name or UDID matches it.
# Without one, picks an available iPhone. Either way a booted device wins, then the
# newest iOS runtime (18.0 or later, the app's deployment target).
set -euo pipefail

want="${1:-}"

udid="$(
  xcrun simctl list devices available --json | jq -r --arg want "$want" '
    [ .devices | to_entries[]
      | select(.key | test("SimRuntime\\.iOS-[0-9-]+$"))
      | (.key | capture("iOS-(?<v>[0-9-]+)$").v | split("-") | map(tonumber)) as $ver
      | select($ver >= [18, 0])
      | .value[] | select(.isAvailable) | . + {ver: $ver} ]
    | map(select(
        if $want == "" then (.deviceTypeIdentifier | test("iPhone"))
        else (.udid == $want or .name == $want) end))
    | sort_by([(if .state == "Booted" then 0 else 1 end), (.ver | map(-.))])
    | .[0].udid // empty'
)"

if [[ -z "$udid" ]]; then
  if [[ -n "$want" ]]; then
    echo "error: no available iOS 18+ simulator named or with UDID '$want'." >&2
  else
    echo "error: no available iOS 18+ iPhone simulator." >&2
  fi
  echo "List devices with: xcrun simctl list devices available" >&2
  exit 1
fi

echo "$udid"
