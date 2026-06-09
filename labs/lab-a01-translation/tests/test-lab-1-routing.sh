#!/usr/bin/env bash
# test-lab-1-routing.sh — verify the "Read the routing table" section of Lab A01.
#
# Checks that the kernel routing table has the expected shape for a container
# attached to a Docker bridge: a default route, a connected subnet route, the
# three standard policy-routing rules, and a populated table local.
#
# Non-destructive and non-modifying. Safe to run at any point.
#
# Usage:  ./tests/test.sh 1

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"

require_cmds ip jq

# ---------------------------------------------------------------------------
section "Routing table shape"
# ---------------------------------------------------------------------------

GW="$(default_gw)"
DEV="$(default_dev)"

if [ -n "$GW" ] && [ -n "$DEV" ]; then
  pass "default route present: via $GW dev $DEV"
else
  fail "no default route found in 'ip route show' — container may not have a gateway"
fi

# Connected route: expect at least one kernel/link-scope route (the bridge subnet)
CONNECTED="$(ip -j route show 2>/dev/null | jq -r '
  .[] | select(.protocol=="kernel" and .scope=="link" and .dst!="default")
  | .dst' | head -n1)"
if [ -n "$CONNECTED" ]; then
  pass "connected (kernel/link-scope) route present: $CONNECTED"
else
  fail "no kernel/link-scope connected route found — eth0 address may be missing"
fi

# ---------------------------------------------------------------------------
section "ip route get — FIB lookup"
# ---------------------------------------------------------------------------

# Route to an external address should use the default route
SRC_EXT="$(route_get_src 1.1.1.1)"
DEV_EXT="$(route_get_dev 1.1.1.1)"
if [ -n "$SRC_EXT" ] && [ -n "$DEV_EXT" ]; then
  pass "ip route get 1.1.1.1 returns src=$SRC_EXT dev=$DEV_EXT"
else
  fail "ip route get 1.1.1.1 returned no result — default route missing or ip -j broken"
fi

# Route to loopback space should resolve to lo
DEV_LO="$(route_get_dev 127.0.0.53)"
if [ "$DEV_LO" = "lo" ]; then
  pass "ip route get 127.0.0.53 correctly resolves to dev=lo"
else
  fail "ip route get 127.0.0.53 returned dev='$DEV_LO', expected 'lo'"
fi

# ---------------------------------------------------------------------------
section "Policy-routing rule database"
# ---------------------------------------------------------------------------

RULES="$(ip -j rule show 2>/dev/null | jq -r '.[].priority' 2>/dev/null | sort -n)"
for want_prio in 0 32766 32767; do
  if printf '%s\n' "$RULES" | grep -qx "$want_prio"; then
    table="$(ip -j rule show 2>/dev/null | jq -r --argjson p "$want_prio" \
      '.[] | select(.priority==$p) | .table // ""' | head -n1)"
    pass "policy rule at priority $want_prio present (table: $table)"
  else
    fail "policy rule at priority $want_prio missing from 'ip rule show'"
  fi
done

# ---------------------------------------------------------------------------
section "Table local"
# ---------------------------------------------------------------------------

LOCAL_COUNT="$(ip -j route show table local 2>/dev/null | jq 'length' 2>/dev/null || echo 0)"
if [ "$LOCAL_COUNT" -ge 1 ]; then
  pass "table local has $LOCAL_COUNT route(s) (kernel auto-populates for assigned addresses)"
else
  fail "table local is empty — expected at least a loopback host route"
fi

# A non-existent table (100) should return an error, not an empty list.
TABLE100_OUT="$(ip route show table 100 2>&1)"
if echo "$TABLE100_OUT" | grep -qi "does not exist\|no such file\|invalid"; then
  pass "table 100 correctly absent ('ip route show table 100' returns an error)"
else
  # Some kernels return an empty result instead of an error — also acceptable
  warn "table 100 returned '$TABLE100_OUT' — expected 'FIB table does not exist' or similar"
fi

finish
