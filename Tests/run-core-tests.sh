#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
test_build="${TMPDIR:-/tmp}/baduy-core-tests"
mkdir -p "$test_build"
xcrun swiftc -parse-as-library -module-cache-path "$test_build/modules" \
 Baduy/Social/Models/Models.swift Baduy/Social/Core/Keychain.swift Baduy/Social/Core/API.swift \
 Baduy/Social/Core/Repository.swift Baduy/Social/Features/AppState.swift Tests/CoreTests.swift \
 -o "$test_build/CoreTests"
"$test_build/CoreTests"
