#!/usr/bin/env bash
# test-lab-12-json.sh — verify the "Structured output and jq" section of Lab A01.
#
# Exercises the ip -j pipeline patterns from the article: full address tree,
# single-interface address extraction, route table as tuples, and interface
# selection by name prefix. All read-only.
#
# Usage:  ./tests/test.sh 12

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"

require_cmds ip jq

# ---------------------------------------------------------------------------
section "ip -j addr show — valid JSON"
# ---------------------------------------------------------------------------

JSON="$(ip -j addr show 2>/dev/null)"
if printf '%s\n' "$JSON" | jq -e 'type == "array"' >/dev/null 2>&1; then
  COUNT="$(printf '%s\n' "$JSON" | jq 'length')"
  pass "ip -j addr show returns valid JSON array ($COUNT interfaces)"
else
  fail "ip -j addr show did not return a JSON array"
fi

# ---------------------------------------------------------------------------
section "ip -j addr show dev eth0 | jq '.[0].addr_info[0].local'"
# ---------------------------------------------------------------------------

LOCAL="$(ip -j addr show dev eth0 2>/dev/null | jq -r '.[0].addr_info[0].local // ""')"
if [[ "$LOCAL" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  pass "extracted eth0 first address via jq: $LOCAL"
else
  fail "jq extraction of eth0 local address returned '$LOCAL', expected an IPv4 address"
fi

# ---------------------------------------------------------------------------
section "ip -j route show | jq '.[] | {dst, gateway, dev, proto}'"
# ---------------------------------------------------------------------------

ROUTES="$(ip -j route show 2>/dev/null | jq -r '.[] | {dst, gateway, dev, proto}' 2>/dev/null)"
if [ -n "$ROUTES" ]; then
  pass "ip -j route show | jq tuple extraction returned output"
  # The default route should appear with dst == "default"
  HAS_DEFAULT="$(ip -j route show 2>/dev/null \
    | jq 'any(.[]; .dst == "default")' 2>/dev/null)"
  if [ "$HAS_DEFAULT" = "true" ]; then
    pass "default route (dst==\"default\") present in JSON route table"
  else
    fail "default route not found in JSON route table"
  fi
else
  fail "ip -j route show | jq returned no output"
fi

# ---------------------------------------------------------------------------
section "ip -j link show | jq select startswith('e')"
# ---------------------------------------------------------------------------

E_IFACES="$(ip -j link show 2>/dev/null \
  | jq -r '.[] | select(.ifname | startswith("e")) | .ifname' 2>/dev/null)"

if printf '%s\n' "$E_IFACES" | grep -qx 'eth0'; then
  pass "jq select-startswith filter found eth0 in interface list"
else
  fail "jq select-startswith filter did not return eth0 (got: ${E_IFACES:-nothing})"
fi

# Verify no interfaces NOT starting with 'e' leaked through the filter
BAD="$(printf '%s\n' "$E_IFACES" | grep -v '^e' | grep -v '^$' || true)"
if [ -z "$BAD" ]; then
  pass "jq filter is precise — no non-'e' interfaces in the result"
else
  fail "jq filter leaked unexpected interfaces: $BAD"
fi

# ---------------------------------------------------------------------------
section "ip -j neigh show — neighbor table as JSON"
# ---------------------------------------------------------------------------

NEIGH_JSON="$(ip -j neigh show 2>/dev/null)"
if printf '%s\n' "$NEIGH_JSON" | jq -e 'type == "array"' >/dev/null 2>&1; then
  pass "ip -j neigh show returns valid JSON array"
else
  fail "ip -j neigh show did not return a valid JSON array"
fi

# ---------------------------------------------------------------------------
section "ip -j rule show — policy-routing rules as JSON"
# ---------------------------------------------------------------------------

RULES_JSON="$(ip -j rule show 2>/dev/null)"
RULE_COUNT="$(printf '%s\n' "$RULES_JSON" | jq 'length' 2>/dev/null || echo 0)"
if [ "$RULE_COUNT" -ge 3 ]; then
  pass "ip -j rule show returns $RULE_COUNT rule(s) as JSON"
else
  fail "ip -j rule show returned $RULE_COUNT rule(s), expected at least 3"
fi

finish
