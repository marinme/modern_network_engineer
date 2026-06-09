#!/usr/bin/env bash
# test-lab-8-sockets.sh — verify the "List sockets" section of Lab A01.
#
# Starts an nc listener on port 8080, verifies ss detects it both with the
# basic form and with the filter syntax, then kills the listener and confirms
# the socket disappears.
#
# Usage:  ./tests/test.sh 8

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"

require_cmds ss nc

TEST_PORT=8080

# ---------------------------------------------------------------------------
section "Pre-condition: port 8080 is not in use"
# ---------------------------------------------------------------------------

if ss_listening_port "$TEST_PORT"; then
  warn "port $TEST_PORT already in use before test — killing any existing listener"
  fuser -k "${TEST_PORT}/tcp" 2>/dev/null || true
  sleep 0.3
fi

if ! ss_listening_port "$TEST_PORT"; then
  pass "port $TEST_PORT is free before test"
else
  fail "port $TEST_PORT still in use — cannot run clean test"
fi

# ---------------------------------------------------------------------------
section "Start nc listener"
# ---------------------------------------------------------------------------

nc -l -p "$TEST_PORT" &
NC_PID=$!
_BG_PIDS+=("$NC_PID")
sleep 0.3

if kill -0 "$NC_PID" 2>/dev/null; then
  pass "nc -l -p $TEST_PORT started (pid $NC_PID)"
else
  fail "nc failed to start — 'nc' may not support -p flag or port $TEST_PORT is blocked"
fi

# ---------------------------------------------------------------------------
section "ss -lntp — basic listening socket view"
# ---------------------------------------------------------------------------

if ss_listening_port "$TEST_PORT"; then
  pass "ss -ltn shows port $TEST_PORT in LISTEN state"
else
  fail "ss -ltn does not show port $TEST_PORT — listener may not be ready yet"
fi

SS_LINE="$(ss -lntp 2>/dev/null | grep ":$TEST_PORT")"
if [ -n "$SS_LINE" ]; then
  info "ss -lntp output: $SS_LINE"
  pass "ss -lntp output line present for :$TEST_PORT"
  # Check that the process name appears
  if printf '%s' "$SS_LINE" | grep -q 'nc\|netcat'; then
    pass "process name (nc/netcat) visible in ss output"
  else
    warn "process name not visible in ss output (may need -p flag and root/ptrace permission)"
  fi
else
  fail "no ss -lntp output line found for :$TEST_PORT"
fi

# ---------------------------------------------------------------------------
section "ss filter syntax — 'sport = :PORT'"
# ---------------------------------------------------------------------------

FILTER_OUT="$(ss -ltn "sport = :$TEST_PORT" 2>/dev/null)"
if printf '%s\n' "$FILTER_OUT" | grep -q ":$TEST_PORT"; then
  pass "ss -ltn 'sport = :$TEST_PORT' filter matches the listener"
else
  fail "ss filter 'sport = :$TEST_PORT' returned no results (ss filter syntax may differ by version)"
fi

# ---------------------------------------------------------------------------
section "Kill listener and verify socket disappears"
# ---------------------------------------------------------------------------

kill "$NC_PID" 2>/dev/null || true
wait "$NC_PID" 2>/dev/null || true
sleep 0.3

if ss_listening_port "$TEST_PORT"; then
  fail "port $TEST_PORT still appears in LISTEN after killing nc"
else
  pass "port $TEST_PORT is gone from ss after killing nc"
fi

finish
