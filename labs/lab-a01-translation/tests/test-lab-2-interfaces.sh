#!/usr/bin/env bash
# test-lab-2-interfaces.sh — verify the "List interfaces and addresses" section.
#
# Checks that lo and eth0 are present, eth0 has an IPv4 address, and the
# detailed link view returns parseable output. Non-destructive, read-only.
#
# Usage:  ./tests/test.sh 2

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"

require_cmds ip jq

# ---------------------------------------------------------------------------
section "ip -br link — interface inventory"
# ---------------------------------------------------------------------------

# veth interfaces appear as "eth0@if7" — strip the @peer suffix for matching.
IFACES="$(ip -br link 2>/dev/null | awk '{print $1}' | sed 's/@.*//' | grep -v '^$')"

for want_if in lo eth0; do
  if printf '%s\n' "$IFACES" | grep -qx "$want_if"; then
    state="$(ip -br link show dev "$want_if" 2>/dev/null | awk '{print $2}')"
    pass "interface $want_if present (state: $state)"
  else
    fail "interface $want_if missing from 'ip -br link'"
  fi
done

# lo must be UP; eth0 must be UP (DOWN would mean no connectivity)
for iface in lo eth0; do
  state="$(ip -br link show dev "$iface" 2>/dev/null | awk '{print $2}')"
  if [ "$state" = "UP" ] || [ "$state" = "UNKNOWN" ]; then
    pass "$iface is UP (state=$state)"
  else
    fail "$iface state is '$state', expected UP — interface may be down"
  fi
done

# ---------------------------------------------------------------------------
section "ip -br addr — address inventory"
# ---------------------------------------------------------------------------

ETH0_IP="$(eth0_ip)"
if [ -n "$ETH0_IP" ]; then
  pass "eth0 has IPv4 address $ETH0_IP"
else
  fail "eth0 has no IPv4 address — container networking may be broken"
fi

LO_ADDR="$(ip -br addr show dev lo 2>/dev/null | awk '{print $3}')"
if [ -n "$LO_ADDR" ]; then
  pass "lo has address $LO_ADDR"
else
  fail "lo has no address — expected at least 127.0.0.1/8"
fi

# ---------------------------------------------------------------------------
section "ip -d link show eth0 — detailed view"
# ---------------------------------------------------------------------------

DETAIL="$(ip -d link show eth0 2>/dev/null)"
if [ -n "$DETAIL" ]; then
  pass "ip -d link show eth0 returned output"
else
  fail "ip -d link show eth0 returned nothing"
fi

# In a Docker container eth0 should be a veth
if printf '%s\n' "$DETAIL" | grep -q 'veth'; then
  pass "eth0 is a veth device (Docker bridge attachment confirmed)"
else
  warn "eth0 link kind not veth — may be a different container runtime or NIC type"
fi

# MTU should be readable and sane (1000 – 9200)
MTU="$(ip -j link show eth0 2>/dev/null | jq -r '.[0].mtu // ""')"
if [[ "$MTU" =~ ^[0-9]+$ ]] && [ "$MTU" -ge 1000 ] && [ "$MTU" -le 9200 ]; then
  pass "eth0 MTU is $MTU (within sane range)"
else
  fail "eth0 MTU '$MTU' is unexpected (want 1000–9200)"
fi

# ---------------------------------------------------------------------------
section "ip addr show dev eth0 — address lifetime"
# ---------------------------------------------------------------------------

ADDR_OUTPUT="$(ip addr show dev eth0 2>/dev/null)"
if printf '%s\n' "$ADDR_OUTPUT" | grep -q 'inet '; then
  pass "ip addr show dev eth0 shows at least one inet address"
else
  fail "ip addr show dev eth0 shows no inet address"
fi

# "forever" lifetime indicates a statically assigned address (not DHCP-leased)
if printf '%s\n' "$ADDR_OUTPUT" | grep -q 'valid_lft forever'; then
  pass "eth0 address has valid_lft forever (statically assigned, no DHCP timer)"
else
  warn "eth0 address does not have valid_lft forever — may be DHCP-assigned (fine, just different)"
fi

finish
