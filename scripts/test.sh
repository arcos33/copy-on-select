#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/gesture-tests
swiftc Sources/CopyOnSelect/HoldPasteGesture.swift Sources/CopyOnSelect/PasteButton.swift \
  Tests/CopyOnSelectTests/HoldPasteGestureTests.swift -o .build/gesture-tests/run
.build/gesture-tests/run
