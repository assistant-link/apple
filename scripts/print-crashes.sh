#!/bin/bash
# Prints the exception, abort message and crashed-thread backtrace of every crash report that a
# test result bundle holds, since `xcodebuild` only says "Test crashed with signal abrt".
#
# Usage: print-crashes.sh RESULT_BUNDLE
set -uo pipefail

bundle="$1"
out="$(mktemp -d)"
xcrun xcresulttool export attachments --path "$bundle" --output-path "$out/attachments" --only-failures \
  > /dev/null 2>&1 || true
xcrun xcresulttool export diagnostics --path "$bundle" --output-path "$out/diagnostics" \
  > /dev/null 2>&1 || true

found=0
while IFS= read -r -d '' file; do
  # An .ips crash report is a JSON header line followed by a JSON body.
  body="$(tail -n +2 "$file")"
  jq -e '.exception' <<< "$body" > /dev/null 2>&1 || continue
  found=1
  echo "=== ${file#"$out"/}"
  jq -r '
    "exception: \(.exception | tojson)",
    "abort message: \(.asi // {} | tojson)",
    "last exception backtrace:",
    (.lastExceptionBacktrace // [] | .[] | "  \(.symbol // "?") \(.symbolLocation // "")"),
    "crashed thread:",
    (.threads[] | select(.triggered) | .frames[] | "  \(.symbol // "?") \(.symbolLocation // "")")
  ' <<< "$body"
done < <(find "$out" -type f -print0)

[[ $found -eq 1 ]] || echo "No crash report found in $bundle; see $out."
