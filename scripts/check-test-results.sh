#!/bin/bash
# Parses xcodebuild test output to determine if any actual test failures occurred.
# xcodebuild may exit non-zero due to test-runner infrastructure errors (e.g., a
# runner-image allocator crash or a test-host launch/teardown failure) even when
# all unit tests pass. This script checks the real test results.
#
# Usage: xcodebuild test ... 2>/dev/null | scripts/check-test-results.sh

OUTPUT=$(cat)

# Read the totals from the LAST "Executed N tests, with M failures" line.
#
# Do NOT sum these lines. xcodebuild prints one per test suite AND one per
# enclosing suite, up to the outermost "All tests", so the same run appears
# several times over: a suite of 18 with 2 failures printed at three nesting
# levels summed to "54 tests, 6 failures". The outermost line is printed last
# and already covers every suite.
LAST_LINE=$(echo "$OUTPUT" | grep 'Executed.*tests.*failures' | tail -1)
TOTAL_TESTS=$(echo "$LAST_LINE" | grep -oE 'Executed [0-9]+ tests' | grep -oE '[0-9]+')
TOTAL_FAILURES=$(echo "$LAST_LINE" | grep -oE 'with [0-9]+ failures' | grep -oE '[0-9]+')
TOTAL_TESTS=${TOTAL_TESTS:-0}
TOTAL_FAILURES=${TOTAL_FAILURES:-0}

# Swift Testing (`@Test`) results are reported separately and do NOT appear in the
# "Executed N tests" lines above, which are XCTest-only. The suite is a mix of
# both, so counting only XCTest meant a failing `@Test` produced "N tests, 0
# failures" and a zero exit — the gate was blind to it.
#
# Swift Testing prints one line per suite plus a run-level total; take the
# run-level line ("Test run with N tests ... passed/failed").
SWIFT_RUN_LINE=$(echo "$OUTPUT" | grep -E 'Test run with [0-9]+ test' | tail -1)
SWIFT_TESTS=$(echo "$SWIFT_RUN_LINE" | grep -oE 'with [0-9]+ test' | grep -oE '[0-9]+')
SWIFT_TESTS=${SWIFT_TESTS:-0}
# Count individual recorded issues rather than trusting the summary wording.
SWIFT_FAILURES=$(echo "$OUTPUT" | grep -cE '✘ Test .* recorded an issue' || true)
SWIFT_FAILURES=${SWIFT_FAILURES:-0}

TOTAL_TESTS=$((TOTAL_TESTS + SWIFT_TESTS))
TOTAL_FAILURES=$((TOTAL_FAILURES + SWIFT_FAILURES))

if [ "$TOTAL_TESTS" -eq 0 ]; then
    echo "error: no test results found"
    exit 1
fi

echo "$TOTAL_TESTS tests, $TOTAL_FAILURES failures ($SWIFT_TESTS via Swift Testing)"

if [ "$TOTAL_FAILURES" -gt 0 ]; then
    # Show failing test details. Matches what xcodebuild actually emits:
    #   /path/File.swift:12: error: -[Suite testName] : failed: ...   (XCTest)
    #   Test Case '-[Suite testName]' failed (0.01 seconds).          (XCTest)
    #   ✘ Test "name" recorded an issue                               (Swift Testing)
    # The previous pattern ("failed -|FAIL") matched none of these, so a failing
    # run printed a count and no detail at all.
    echo "$OUTPUT" | grep -E "error:.*: failed|Test Case .* failed|✘ Test .* recorded an issue" || true
    exit 1
fi

exit 0
