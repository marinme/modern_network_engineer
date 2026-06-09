#!/usr/bin/env bash
# test-lab-5-static-routes.sh — verify the "Add and remove a static route" section.
#
# Adds 198.51.100.0/24 via the gateway, verifies it with ip route show and
# ip route get, replaces it with an mtu 1400 attribute, then deletes it.
# All state is restored on exit.
#
# With --inject-fault: skips the `ip route add` step so verification checks
# fail, demonstrating what a missing route entry looks like.
#
# Usage:
#   ./tests/test.sh 5                # normal run
#   ./tests/test.sh 5 --inject-fault # fault demo (skip add → show failures)

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"

require_cmds ip jq

FAULT=0
[[ "${1:-}" == "--inject-fault" ]] && FAULT=1

TEST_PREFIX="198.51.100.0/24"
TEST_REMOTE="198.51.100.42"

# ---------------------------------------------------------------------------
section "Discover gateway"
# ---------------------------------------------------------------------------

GW="$(default_gw)"
DEV="$(default_dev)"
[ -n "$GW" ] || die "no default gateway — cannot add static route"
info "gateway: $GW dev $DEV"

# Clean up any leftover from a previous run
ip route del "$TEST_PREFIX" 2>/dev/null || true

# ---------------------------------------------------------------------------
section "Add static route"
# ---------------------------------------------------------------------------

if [ "$FAULT" -eq 1 ]; then
  warn "FAULT INJECTION: skipping 'ip route add $TEST_PREFIX via $GW'"
  warn "The following checks should FAIL — this demonstrates the failure mode."
else
  ip route add "$TEST_PREFIX" via "$GW" dev "$DEV" proto static \
    && info "added $TEST_PREFIX via $GW proto static" \
    || die "ip route add failed — NET_ADMIN required"
fi

# ---------------------------------------------------------------------------
section "Verify route in table"
# ---------------------------------------------------------------------------

if has_route "$TEST_PREFIX"; then
  pass "$TEST_PREFIX is present in the routing table"
else
  fail "$TEST_PREFIX is NOT in the routing table — route add may have failed"
fi

PROTO="$(route_proto "$TEST_PREFIX")"
if [ "$PROTO" = "static" ]; then
  pass "route proto is 'static' (matches IOS 'S' source flag)"
else
  fail "route proto is '$PROTO', expected 'static'"
fi

# ---------------------------------------------------------------------------
section "ip route get resolves through the new route"
# ---------------------------------------------------------------------------

DEV_USED="$(route_get_dev "$TEST_REMOTE")"
SRC_USED="$(route_get_src "$TEST_REMOTE")"
if [ "$DEV_USED" = "$DEV" ] && [ -n "$SRC_USED" ]; then
  pass "ip route get $TEST_REMOTE uses dev=$DEV_USED src=$SRC_USED"
else
  fail "ip route get $TEST_REMOTE returned dev='$DEV_USED' src='$SRC_USED', expected dev=$DEV"
fi

# ---------------------------------------------------------------------------
section "ip route replace — update attribute in place"
# ---------------------------------------------------------------------------

if [ "$FAULT" -eq 0 ]; then
  ip route replace "$TEST_PREFIX" via "$GW" dev "$DEV" proto static mtu 1400 \
    && info "replaced $TEST_PREFIX with mtu 1400" \
    || warn "ip route replace returned non-zero"
fi

# There should be exactly one entry for the prefix (replace is atomic)
ROUTE_COUNT="$(ip -j route show "$TEST_PREFIX" 2>/dev/null | jq 'length' 2>/dev/null || echo 0)"
if [ "$FAULT" -eq 0 ]; then
  if [ "$ROUTE_COUNT" -eq 1 ]; then
    pass "exactly one route entry for $TEST_PREFIX after replace (no duplicates)"
  else
    fail "found $ROUTE_COUNT route entries for $TEST_PREFIX after replace (expected 1)"
  fi

  # iproute2 encodes metrics as an array: [{mtu:N}], not as an object.
  MTU="$(ip -j route show "$TEST_PREFIX" 2>/dev/null \
    | jq -r '.[0] | (.mtu // (.metrics // [] | map(.mtu) | .[0]) // "") | tostring' 2>/dev/null)"
  if [ "$MTU" = "1400" ]; then
    pass "route mtu attribute is 1400 after replace"
  else
    fail "route mtu is '$MTU', expected 1400 after 'ip route replace … mtu 1400'"
  fi
fi

# ---------------------------------------------------------------------------
section "Delete route and verify gone"
# ---------------------------------------------------------------------------

if [ "$FAULT" -eq 0 ]; then
  ip route del "$TEST_PREFIX" \
    || warn "ip route del returned non-zero"
fi

if has_route "$TEST_PREFIX"; then
  if [ "$FAULT" -eq 0 ]; then
    fail "$TEST_PREFIX still in routing table after delete"
  else
    fail "$TEST_PREFIX appeared in the routing table unexpectedly (fault mode)"
  fi
else
  if [ "$FAULT" -eq 0 ]; then
    pass "$TEST_PREFIX removed from routing table"
  else
    pass "$TEST_PREFIX absent from routing table (as expected — never added)"
  fi
fi

finish
