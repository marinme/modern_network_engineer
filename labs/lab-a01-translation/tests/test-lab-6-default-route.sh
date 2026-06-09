#!/usr/bin/env bash
# test-lab-6-default-route.sh — verify the "Break it and put it back" section.
#
# This test INTENTIONALLY exercises both the failure state and the recovery,
# matching the lab exercise exactly:
#   1. Record the default route.
#   2. Delete it → verify reachability is broken.
#   3. Restore it → verify reachability is restored.
#
# The failure state is a core part of the test — it is expected and deliberate.
# Exit 0 means both the "broken" and "fixed" states were verified correctly.
#
# Usage:  ./tests/test.sh 6

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"

require_cmds ip jq ping

# ---------------------------------------------------------------------------
section "Record current default route"
# ---------------------------------------------------------------------------

GW="$(default_gw)"
DEV="$(default_dev)"

if [ -n "$GW" ] && [ -n "$DEV" ]; then
  pass "default route exists before test: via $GW dev $DEV"
else
  die "no default route to begin with — cannot run break/restore test"
fi

# ---------------------------------------------------------------------------
section "Break: delete the default route"
# ---------------------------------------------------------------------------

ip route del default \
  && info "default route deleted" \
  || die "ip route del default failed — NET_ADMIN required"

# Verify no default route remains
GW_AFTER="$(default_gw)"
if [ -z "$GW_AFTER" ]; then
  pass "BREAK confirmed: default route is absent"
else
  fail "default route still present after 'ip route del default' (gw: $GW_AFTER)"
fi

# ---------------------------------------------------------------------------
section "Break: verify external reachability is gone"
# ---------------------------------------------------------------------------

# ping_unreachable checks for "Network is unreachable" — the kernel's response
# when there is no matching route, as opposed to a timeout (host down).
if ping_unreachable 1.1.1.1; then
  pass "BREAK confirmed: ping 1.1.1.1 returns 'Network is unreachable' (no route)"
else
  # Fallback: some kernels emit a different message; check for total failure.
  if ! ping -c 1 -W 1 1.1.1.1 >/dev/null 2>&1; then
    pass "BREAK confirmed: ping 1.1.1.1 fails (no route — exact error message differs by kernel)"
  else
    fail "ping 1.1.1.1 still succeeded after deleting the default route — unexpected"
  fi
fi

# ---------------------------------------------------------------------------
section "Fix: restore the default route"
# ---------------------------------------------------------------------------

ip route add default via "$GW" dev "$DEV" \
  && info "default route restored: via $GW dev $DEV" \
  || die "ip route add default via $GW failed — cannot restore"

GW_BACK="$(default_gw)"
if [ "$GW_BACK" = "$GW" ]; then
  pass "FIX confirmed: default route is back (via $GW_BACK)"
else
  fail "default route gateway mismatch after restore: got '$GW_BACK', expected '$GW'"
fi

# ---------------------------------------------------------------------------
section "Fix: verify external reachability is restored"
# ---------------------------------------------------------------------------

# Use loopback-only ping if 1.1.1.1 is blocked by the network environment.
# Gateway ping is the strongest proof; loopback is a fallback that at least
# proves the stack is up and the route changes took effect.
if ping_ok 1.1.1.1 2; then
  pass "FIX confirmed: ping 1.1.1.1 succeeds after restoring default route"
elif ping_ok "$GW" 2; then
  pass "FIX confirmed: ping gateway $GW succeeds (1.1.1.1 may be filtered by your network)"
else
  fail "FIX failed: cannot ping $GW or 1.1.1.1 after restoring the default route"
fi

finish
