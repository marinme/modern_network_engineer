#!/usr/bin/env bash
# test-lab-3-addr-lifecycle.sh — verify the "Add and remove an address" section.
#
# Adds 192.0.2.1/24 to lo, verifies it appears and that ip route get resolves
# through it, then removes it and verifies it is gone.
#
# With --inject-fault: skips the `ip addr add` step so the checks fail,
# demonstrating what a missing address looks like. The fault leaves no lasting
# state (the address was never added).
#
# Usage:
#   ./tests/test.sh 3                # normal run (add → verify → remove)
#   ./tests/test.sh 3 --inject-fault # fault demo (skip add → show failures)

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"

require_cmds ip jq

FAULT=0
[[ "${1:-}" == "--inject-fault" ]] && FAULT=1

TEST_ADDR="192.0.2.1"
TEST_CIDR="192.0.2.1/24"
TEST_REMOTE="192.0.2.99"

# ---------------------------------------------------------------------------
section "Setup"
# ---------------------------------------------------------------------------

# Ensure we start clean — remove the address if a previous run left it.
if has_addr lo "$TEST_CIDR"; then
  info "cleaning up leftover $TEST_CIDR on lo from a previous run"
  ip addr del "$TEST_CIDR" dev lo 2>/dev/null || true
fi

if [ "$FAULT" -eq 1 ]; then
  warn "FAULT INJECTION: skipping 'ip addr add $TEST_CIDR dev lo'"
  warn "The following checks should FAIL — this demonstrates the failure mode."
else
  ip addr add "$TEST_CIDR" dev lo 2>/dev/null \
    && info "added $TEST_CIDR to lo" \
    || die "ip addr add $TEST_CIDR dev lo failed — are you running with NET_ADMIN?"
fi

# ---------------------------------------------------------------------------
section "Verify address is present"
# ---------------------------------------------------------------------------

if has_addr lo "$TEST_CIDR"; then
  pass "$TEST_CIDR is assigned to lo"
else
  fail "$TEST_CIDR is NOT assigned to lo — 'ip addr add' may have failed"
fi

LO_ADDRS="$(addr_on_dev lo | tr '\n' ' ')"
if printf '%s' "$LO_ADDRS" | grep -q "$TEST_ADDR"; then
  pass "ip -br addr shows $TEST_ADDR on lo"
else
  fail "ip -br addr does not show $TEST_ADDR on lo (saw: $LO_ADDRS)"
fi

# ---------------------------------------------------------------------------
section "ip route get resolves via the new address"
# ---------------------------------------------------------------------------

SRC="$(route_get_src "$TEST_REMOTE")"
DEV="$(route_get_dev "$TEST_REMOTE")"
if [ "$SRC" = "$TEST_ADDR" ] && [ "$DEV" = "lo" ]; then
  pass "ip route get $TEST_REMOTE: src=$SRC dev=$DEV (resolves via $TEST_CIDR)"
else
  fail "ip route get $TEST_REMOTE: src='$SRC' dev='$DEV' — expected src=$TEST_ADDR dev=lo"
fi

# ---------------------------------------------------------------------------
section "Remove address and verify it is gone"
# ---------------------------------------------------------------------------

if [ "$FAULT" -eq 0 ]; then
  ip addr del "$TEST_CIDR" dev lo 2>/dev/null \
    || warn "ip addr del returned non-zero (address may already be absent)"
fi

if has_addr lo "$TEST_CIDR"; then
  fail "$TEST_CIDR still present on lo after 'ip addr del' — del may have failed"
else
  if [ "$FAULT" -eq 0 ]; then
    pass "$TEST_CIDR successfully removed from lo"
  else
    pass "$TEST_CIDR absent from lo (as expected — it was never added)"
  fi
fi

finish
