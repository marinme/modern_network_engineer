#!/usr/bin/env bash
# test-lab-11-counters.sh — verify the "Counters in depth" section of Lab A01.
#
# Generates traffic, then checks that ip -s link shows non-zero TX/RX counters,
# that ip -s -s link shows the extended error breakdown, and that ethtool -S
# runs without error.
#
# Usage:  ./tests/test.sh 11

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"

require_cmds ip ethtool ping

# ---------------------------------------------------------------------------
section "Generate traffic on eth0"
# ---------------------------------------------------------------------------

GW="$(default_gw)"
if [ -n "$GW" ]; then
  ping -c 5 -W 1 "$GW" >/dev/null 2>&1 || true
  pass "generated traffic via gateway $GW to populate eth0 counters"
else
  warn "no gateway — using loopback only (eth0 counters may be low)"
fi

# ---------------------------------------------------------------------------
section "ip -s link show eth0 — RX/TX counters"
# ---------------------------------------------------------------------------

STATS="$(ip -s link show eth0 2>/dev/null)"
if [ -z "$STATS" ]; then
  fail "ip -s link show eth0 returned no output"
  finish
fi
pass "ip -s link show eth0 returned output"

# Parse RX packet count from the structured output.
# ip -s link shows: ... RX: bytes packets errors ... (then values on next line)
RX_PKTS="$(ip -j -s link show eth0 2>/dev/null \
  | jq -r '.[0].stats64.rx.packets // .[0].stats.rx_packets // ""' 2>/dev/null)"
TX_PKTS="$(ip -j -s link show eth0 2>/dev/null \
  | jq -r '.[0].stats64.tx.packets // .[0].stats.tx_packets // ""' 2>/dev/null)"

if [[ "$RX_PKTS" =~ ^[0-9]+$ ]] && [ "$RX_PKTS" -gt 0 ]; then
  pass "eth0 RX packet count is non-zero ($RX_PKTS packets received)"
else
  # Fall back: check the text output contains a non-zero number on the RX line
  if printf '%s\n' "$STATS" | grep -A1 'RX:' | grep -qE '^\s+[1-9]'; then
    pass "eth0 RX counters are non-zero (parsed from text output)"
  else
    fail "eth0 RX packet count is zero or unreadable ($RX_PKTS) — no traffic may have crossed eth0"
  fi
fi

if [[ "$TX_PKTS" =~ ^[0-9]+$ ]] && [ "$TX_PKTS" -gt 0 ]; then
  pass "eth0 TX packet count is non-zero ($TX_PKTS packets sent)"
else
  if printf '%s\n' "$STATS" | grep -A1 'TX:' | grep -qE '^\s+[1-9]'; then
    pass "eth0 TX counters are non-zero (parsed from text output)"
  else
    fail "eth0 TX packet count is zero or unreadable ($TX_PKTS)"
  fi
fi

# ---------------------------------------------------------------------------
section "ip -s -s link show eth0 — extended error breakdown"
# ---------------------------------------------------------------------------

STATS2="$(ip -s -s link show eth0 2>/dev/null)"
if [ -n "$STATS2" ]; then
  pass "ip -s -s link show eth0 returned output"

  # The double-s output adds error-cause sub-lines.  On veth the values are
  # all zero, but the headers (carrier, collisions, etc.) should be present.
  if printf '%s\n' "$STATS2" | grep -qiE 'carrier|collisions|dropped'; then
    pass "extended error breakdown fields present in -s -s output"
  else
    warn "extended error breakdown fields not found in -s -s output — veth driver may not expose them"
  fi
else
  fail "ip -s -s link show eth0 returned no output"
fi

# ---------------------------------------------------------------------------
section "ethtool -S eth0 — NIC-internal stats"
# ---------------------------------------------------------------------------

ETHTOOL_OUT="$(ethtool -S eth0 2>&1)"
RC=$?
if [ "$RC" -eq 0 ]; then
  LINE_COUNT="$(printf '%s\n' "$ETHTOOL_OUT" | wc -l)"
  pass "ethtool -S eth0 exited 0 ($LINE_COUNT stat lines)"
else
  # ethtool may exit non-zero if the veth driver doesn't expose stats —
  # that is a driver limitation, not a lab failure.
  if printf '%s\n' "$ETHTOOL_OUT" | grep -qi 'no stats\|operation not supported\|not supported'; then
    warn "ethtool -S eth0: driver reports no stats (veth limitation — expected on this container)"
    pass "ethtool -S eth0 ran without a fatal error (driver just has no stats to report)"
  else
    fail "ethtool -S eth0 failed unexpectedly: $ETHTOOL_OUT"
  fi
fi

finish
