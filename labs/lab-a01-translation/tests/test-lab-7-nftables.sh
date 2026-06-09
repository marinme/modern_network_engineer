#!/usr/bin/env bash
# test-lab-7-nftables.sh — verify the "Read an nftables ruleset" section.
#
# Normal run: starts from an empty ruleset, builds the three-rule example from
# the article, verifies counters increment when traffic hits the right rule,
# then flushes everything.
#
# With --inject-fault: installs a policy-drop chain WITHOUT the ct state rule
# before building, so return traffic is dropped and the counter check fails.
# Demonstrates what a mis-ordered or incomplete ruleset looks like.
# The fault is cleaned up on exit regardless.
#
# Usage:
#   ./tests/test.sh 7                # normal run
#   ./tests/test.sh 7 --inject-fault # fault demo

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"

require_cmds nft jq ping

FAULT=0
[[ "${1:-}" == "--inject-fault" ]] && FAULT=1

# Always flush on exit so we don't leave firewall rules behind.
_nft_cleanup() {
  nft flush ruleset 2>/dev/null || true
  _cleanup   # lib.sh trap
}
trap _nft_cleanup EXIT INT TERM

GW="$(default_gw)"

# ---------------------------------------------------------------------------
section "Pre-condition: start from an empty ruleset"
# ---------------------------------------------------------------------------

nft flush ruleset 2>/dev/null || die "nft flush ruleset failed — nftables not available"

COUNT_BEFORE="$(nft_rule_count)"
if [ "$COUNT_BEFORE" -eq 0 ]; then
  pass "ruleset is empty before test (COUNT=$COUNT_BEFORE)"
else
  fail "ruleset has $COUNT_BEFORE rule(s) before test — flush may have failed"
fi

# ---------------------------------------------------------------------------
section "Fault injection (if requested)"
# ---------------------------------------------------------------------------

if [ "$FAULT" -eq 1 ]; then
  warn "FAULT INJECTION: installing policy-drop chain WITHOUT the ct state rule"
  warn "Return traffic will be dropped — the eth0 ping counter check should FAIL."
  nft add table inet filter
  nft 'add chain inet filter input { type filter hook input priority 0; policy drop; }'
  # Intentionally omit:  ct state established,related counter accept
  nft 'add rule inet filter input iif lo counter accept'
  info "injected ruleset (missing ct state rule):"
  nft list ruleset 2>/dev/null | sed 's/^/    /'
fi

# ---------------------------------------------------------------------------
section "Build the article's three-rule ruleset"
# ---------------------------------------------------------------------------

if nft_table_exists inet filter; then
  info "table inet filter already exists (from fault injection)"
else
  nft add table inet filter \
    || die "nft add table failed"
fi

# Add the chain if not present
if ! nft list chain inet filter input 2>/dev/null | grep -q 'hook input'; then
  nft 'add chain inet filter input { type filter hook input priority 0; policy drop; }' \
    || die "nft add chain failed"
fi

# Add the three rules (idempotent — if the chain already has rules from fault
# injection they are still there; the new rules are appended below them)
nft 'add rule inet filter input ct state established,related counter accept' || die "nft add rule ct failed"
nft 'add rule inet filter input iif lo counter accept' 2>/dev/null || true  # may already exist from fault injection
nft "add rule inet filter input ip saddr $(default_gw | sed 's/\.[0-9]*$/\.0/')/16 tcp dport 22 counter accept" \
  2>/dev/null || nft 'add rule inet filter input tcp dport 22 counter accept'

RULE_COUNT="$(nft_rule_count)"
if [ "$RULE_COUNT" -ge 3 ]; then
  pass "ruleset has $RULE_COUNT rule(s) after building the example"
else
  fail "ruleset has only $RULE_COUNT rule(s), expected ≥ 3"
fi

# ---------------------------------------------------------------------------
section "Verify counters — loopback ping hits 'iif lo' rule"
# ---------------------------------------------------------------------------

# Reset counters so we get clean numbers
nft reset counters 2>/dev/null || true

ping -c 1 -W 1 127.0.0.1 >/dev/null 2>&1 || true

# nftables quotes the interface: 'iif "lo"' — use a regex that matches both.
LO_PKTS="$(nft_counter_packets 'iif.*lo.*counter')"
if [ "${LO_PKTS:-0}" -ge 1 ]; then
  pass "iif lo rule counter incremented to $LO_PKTS packet(s) after loopback ping"
else
  fail "iif lo rule counter is $LO_PKTS after loopback ping — rule may not be matching"
fi

# ---------------------------------------------------------------------------
section "Verify counters — gateway ping hits 'ct state established,related' rule"
# ---------------------------------------------------------------------------

if [ -n "$GW" ]; then
  nft reset counters 2>/dev/null || true
  ping -c 1 -W 2 "$GW" >/dev/null 2>&1 || true
  sleep 0.1

  CT_PKTS="$(nft_counter_packets 'ct state')"
  if [ "${CT_PKTS:-0}" -ge 1 ]; then
    pass "ct state rule counter incremented to $CT_PKTS packet(s) after gateway ping"
  else
    fail "ct state rule counter is $CT_PKTS after gateway ping — stateful tracking may be missing or counter reset"
  fi
else
  warn "no gateway detected — skipping gateway-ping counter check"
fi

# ---------------------------------------------------------------------------
section "Flush ruleset and verify empty"
# ---------------------------------------------------------------------------

nft flush ruleset 2>/dev/null || warn "nft flush ruleset returned non-zero"

COUNT_AFTER="$(nft_rule_count)"
if [ "$COUNT_AFTER" -eq 0 ]; then
  pass "ruleset empty after 'nft flush ruleset'"
else
  fail "ruleset still has $COUNT_AFTER rule(s) after flush"
fi

finish
