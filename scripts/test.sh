#!/bin/bash
# Control - Test Runner
# Usage: ./scripts/test.sh [unit|integration|all]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

TEST_TYPE="${1:-all}"

cd "$PROJECT_DIR"

echo "Running Control tests ($TEST_TYPE)..."

case "$TEST_TYPE" in
    unit)
        swift test --filter ControlTests
        ;;
    integration)
        swift test --filter ControlIntegrationTests
        ;;
    all)
        swift test
        ;;
    coverage)
        swift test --enable-code-coverage
        # Extract coverage report
        xcrun llvm-cov report \
            .build/debug/ControlPackageTests.xctest/Contents/MacOS/ControlPackageTests \
            -instr-profile=.build/debug/codecov/default.profdata \
            -ignore-filename-regex=".build|Tests"
        ;;
    *)
        echo "Usage: $0 [unit|integration|all|coverage]"
        exit 1
        ;;
esac

echo "Tests complete"
