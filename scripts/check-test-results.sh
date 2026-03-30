#!/bin/bash
# Parses xcodebuild test output to determine if any actual test failures occurred.
# xcodebuild may exit non-zero due to device communication errors (e.g., locked iPhone)
# even when all unit tests pass. This script checks the real test results.
#
# Usage: xcodebuild test ... 2>/dev/null | scripts/check-test-results.sh

OUTPUT=$(cat)

# Count total tests and failures from "Executed N tests, with M failures" lines
TOTAL_TESTS=0
TOTAL_FAILURES=0

while IFS= read -r line; do
    tests=$(echo "$line" | grep -oE 'Executed [0-9]+ tests' | grep -oE '[0-9]+')
    failures=$(echo "$line" | grep -oE 'with [0-9]+ failures' | grep -oE '[0-9]+')
    if [ -n "$tests" ] && [ -n "$failures" ]; then
        TOTAL_TESTS=$((TOTAL_TESTS + tests))
        TOTAL_FAILURES=$((TOTAL_FAILURES + failures))
    fi
done <<< "$(echo "$OUTPUT" | grep 'Executed.*tests.*failures')"

if [ "$TOTAL_TESTS" -eq 0 ]; then
    echo "error: no test results found"
    exit 1
fi

echo "$TOTAL_TESTS tests, $TOTAL_FAILURES failures"

if [ "$TOTAL_FAILURES" -gt 0 ]; then
    # Show failing test details
    echo "$OUTPUT" | grep -E "(failed -|FAIL)" || true
    exit 1
fi

exit 0
