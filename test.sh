#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/BashMacDulerTests.XXXXXX")"
trap 'rm -rf "$TEMP_ROOT"' EXIT

cd "$ROOT"

xcrun swiftc -swift-version 5 -parse-as-library \
    Sources/ScriptItem.swift Sources/ScheduleCalculator.swift Tests/ScheduleTests.swift \
    -o "$TEMP_ROOT/schedule-tests"
"$TEMP_ROOT/schedule-tests"

xcrun swiftc -swift-version 5 -parse-as-library \
    Sources/ScriptItem.swift Sources/ScheduleCalculator.swift Sources/ScriptStore.swift \
    Sources/ScriptRunner.swift Tests/RunnerTests.swift \
    -framework AppKit -framework SwiftUI \
    -o "$TEMP_ROOT/runner-tests"
"$TEMP_ROOT/runner-tests"
