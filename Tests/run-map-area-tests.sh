#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
test_build="${TMPDIR:-/tmp}/baduy-map-area-tests"
mkdir -p "$test_build"
xcrun swiftc -parse-as-library -module-cache-path "$test_build/modules" \
 Baduy/Model/MapLandmark.swift \
 Baduy/Social/Features/MapAreaPolicy.swift Tests/MapAreaTests.swift -o "$test_build/MapAreaTests"
"$test_build/MapAreaTests"
