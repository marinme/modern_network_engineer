#!/usr/bin/env bash
# test-lab-4-neighbors.sh — verify the "Read and manipulate the neighbor table" section.
#
# Flushes the eth0 ARP table, confirms it is empty, pings the gateway to
# populate it, verifies a REACHABLE entry, then adds and removes a static
# (PERMANENT) entry. All state is restored on exit.
#
# Usage:  ./tests/test.sh 4

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"

require_cmds ip jq ping

STATIC_IP="172.17.99.99"
STATIC_MAC="00:11:22:33:44:55"

# ---------------------------------------------------------------------------
section "Discover gateway"
# ---------------------------------------------------------------------------

GW="$(default_gw)"
[ -n "$GW" ] || die "no default gateway — cannot discover neighbor target"
info "gateway: $GW"

# ---------------------------------------------------------------------------
section "Flush and verify empty neighbor table"
# ---------------------------------------------------------------------------

ip neigh flush dev eth0 2>/dev/null || true
sleep 0.2

# Count non-permanent neighbors on eth0 after flush
NEIGH_COUNT="$(ip -j neigh show dev eth0 2>/dev/null \
  | jq '[.[] | select(.state | map(. != "PERMANENT") | any)] | length' 2>/dev/null || echo 0)"

if [ "$NEIGH_COUNT" -eq 0 ]; then
  pass "neighbor table empty after 'ip neigh flush dev eth0' ($NEIGH_COUNT dynamic entries)"
else
  warn "neighbor table has $NEIGH_COUNT dynamic entries after flush (may be kernel-internal entries)"
fi

# ---------------------------------------------------------------------------
section "Ping gateway and verify entry is learned"
# ---------------------------------------------------------------------------

ping -c 1 -W 2 "$GW" >/dev/null 2>&1 || warn "ping $GW failed — ARP may not populate"
sleep 0.3

GW_STATE="$(neigh_state "$GW")"
if [ "$GW_STATE" = "REACHABLE" ] || [ "$GW_STATE" = "STALE" ] || [ "$GW_STATE" = "DELAY" ]; then
  pass "gateway $GW appears in neighbor table (state: $GW_STATE)"
else
  fail "gateway $GW not found in neighbor table after ping (state: '${GW_STATE:-not found}')"
fi

# ---------------------------------------------------------------------------
section "Static (PERMANENT) neighbor entry"
# ---------------------------------------------------------------------------

# Remove leftover from previous run if any
ip neigh del "$STATIC_IP" dev eth0 2>/dev/null || true

ip neigh add "$STATIC_IP" lladdr "$STATIC_MAC" dev eth0 \
  && info "added static entry $STATIC_IP lladdr $STATIC_MAC" \
  || die "ip neigh add failed — NET_ADMIN required"

STATE="$(neigh_state "$STATIC_IP")"
if [ "$STATE" = "PERMANENT" ]; then
  pass "static entry $STATIC_IP shows state PERMANENT"
else
  fail "static entry $STATIC_IP shows state '${STATE:-missing}', expected PERMANENT"
fi

MAC_SEEN="$(ip -j neigh show dev eth0 2>/dev/null \
  | jq -r --arg ip "$STATIC_IP" '.[] | select(.dst==$ip) | .lladdr // ""')"
if [ "${MAC_SEEN,,}" = "${STATIC_MAC,,}" ]; then
  pass "static entry MAC address matches ($MAC_SEEN)"
else
  fail "static entry MAC mismatch: got '$MAC_SEEN', expected '$STATIC_MAC'"
fi

# ---------------------------------------------------------------------------
section "Delete static entry"
# ---------------------------------------------------------------------------

ip neigh del "$STATIC_IP" dev eth0 \
  || warn "ip neigh del returned non-zero"

GONE="$(ip -j neigh show dev eth0 2>/dev/null \
  | jq -r --arg ip "$STATIC_IP" '[.[] | select(.dst==$ip)] | length')"
if [ "${GONE:-1}" -eq 0 ]; then
  pass "static entry $STATIC_IP successfully removed"
else
  fail "static entry $STATIC_IP still present after delete"
fi

finish
