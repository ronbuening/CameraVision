#!/usr/bin/env bash
#
# Format (or lint) Swift sources with the toolchain's swift-format, using the
# repo-root .swift-format configuration (4-space indent, 120-col lines).
#
#   Scripts/format.sh          Format all Swift source, test, script, benchmark, and manifest files in place.
#   Scripts/format.sh --lint   Check only; exit non-zero on any violation.
#
# swift-format ships with the Swift 6 toolchain, so no extra install is needed.
# If XCTest/toolchain resolution needs a full Xcode, prefix with
# DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer (see README).

set -euo pipefail

cd "$(dirname "$0")/.."

paths=(Package.swift Sources Tests Scripts benchmarks)

if [[ "${1:-}" == "--lint" ]]; then
    swift format lint --strict --recursive "${paths[@]}"
else
    swift format --in-place --recursive "${paths[@]}"
    echo "Formatted: ${paths[*]}"
fi
