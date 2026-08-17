#!/usr/bin/env bash
#
# Preflight for `make test-ui`.
#
# XCUITest launches its own copy of WolfWave Dev and attaches to it. When
# something about an existing debug session gets in the way, the failure it
# reports names nothing:
#
#   The test runner failed to initialize for UI testing.
#   (Underlying Error: Timed out while enabling automation mode.)
#
# It arrives after a full build and looks identical to a broken test target.
# This check trades that for one sentence.
#
# What is actually established, and what is not:
#
#   * ESTABLISHED: a copy merely BEING TRACED (state flag `X`, running under
#     Xcode but not stopped) was present for a run that PASSED. Tracing alone
#     does not block, so that case only warns.
#   * ESTABLISHED: runs failed this way while an Xcode debug session was live
#     and had halted the app at a signal; they passed after that session ended.
#   * NOT ESTABLISHED: that a halted app reports process state `T`. Sending
#     SIGSTOP to a traced process does not produce `T` (the debugger intercepts
#     it), and forcing a real Xcode pause to check was not worth the round trip.
#
# ponytail: so the `T` branch below is the best available proxy for "halted",
# not a confirmed reproduction. It is cheap, it cannot fire on a healthy run,
# and the warning path covers the case it misses. Bypass with
# WOLFWAVE_SKIP_UI_PREFLIGHT=1.

set -euo pipefail

if [[ "${WOLFWAVE_SKIP_UI_PREFLIGHT:-0}" == "1" ]]; then
  exit 0
fi

app_pids="$(pgrep -f 'WolfWave Dev.app/Contents/MacOS/WolfWave Dev' 2>/dev/null || true)"

if [[ -z "$app_pids" ]]; then
  exit 0
fi

paused=""
traced=""

for pid in $app_pids; do
  # macOS ps STATE: first letter is the run state (`T` = stopped), and `X`
  # anywhere in the field means the process is being traced or debugged.
  state="$(ps -o state= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
  [[ -z "$state" ]] && continue
  case "$state" in
    T*) paused="$paused $pid" ;;
    *X*) traced="$traced $pid" ;;
  esac
done

if [[ -n "$paused" ]]; then
  cat >&2 <<MSG
error: WolfWave Dev is paused in the debugger (pid$paused).

XCUITest cannot bring up its own copy of the app while one is stopped at a
breakpoint or a signal. The run would fail after a full build with the
unhelpful "Timed out while enabling automation mode".

Fix: in Xcode, either continue (Cmd+Ctrl+Y) or stop (Cmd+.), then confirm the
app actually exited:

    pgrep -lf 'WolfWave Dev'

Stop detaches the debugger but does not always terminate the app. Quit any copy
that survives.

Bypass with WOLFWAVE_SKIP_UI_PREFLIGHT=1.
MSG
  exit 1
fi

if [[ -n "$traced" ]]; then
  echo "warning: WolfWave Dev is running under a debugger (pid$traced)." >&2
  echo "warning: a run has succeeded in this state, but if it fails with 'Timed out while" >&2
  echo "warning: enabling automation mode', stop the Xcode session and quit the app first." >&2
  exit 0
fi

echo "warning: a copy of WolfWave Dev is already running (pid $(echo "$app_pids" | tr '\n' ' '))." >&2
echo "warning: it competes for focus with the app under test. Quitting it makes the run more reliable." >&2
