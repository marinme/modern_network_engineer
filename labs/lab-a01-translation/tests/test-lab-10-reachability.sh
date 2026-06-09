#!/usr/bin/env bash
# test-lab-10-reachability.sh — verify the "Reachability" section of Lab A01.
#
# Checks ping and mtr against loopback (always works) and the Docker gateway
# (works when default Docker networking is present). External destinations
# (1.1.1.1) are tested but allowed to fail with a warning — corporate networks
# and some VPN profiles block outbound ICMP.
#
# Usage:  ./tests/test.sh 10

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"

require_cmds ping mtr

GW="$(default_gw)"

# ---------------------------------------------------------------------------
section "ping — loopback (always reachable)"
# ---------------------------------------------------------------------------

if ping_ok 127.0.0.1 3; then
  LOSS="$(ping -c 3 -W 1 -n 127.0.0.1 2>/dev/null \
    | grep -oE '[0-9]+% packet loss' | grep -oE '^[0-9]+')"
  pass "ping 127.0.0.1: ${LOSS:-0}% loss (loopback always reachable)"
else
  fail "ping 127.0.0.1 failed — loopback is broken, which is very unusual"
fi

# ---------------------------------------------------------------------------
section "ping — Docker gateway"
# ---------------------------------------------------------------------------

if [ -n "$GW" ]; then
  if ping_ok "$GW" 3; then
    pass "ping $GW (gateway): reachable"
  else
    fail "ping $GW (gateway): unreachable — default Docker bridge may be missing"
  fi
else
  warn "no default gateway — skipping gateway ping"
fi

# ---------------------------------------------------------------------------
section "ping — external (1.1.1.1)"
# ---------------------------------------------------------------------------

if ping_ok 1.1.1.1 3; then
  pass "ping 1.1.1.1: reachable (egress ICMP works)"
else
  warn "ping 1.1.1.1 failed — external ICMP may be blocked by your network (not a lab error)"
  info "verify with: curl -sS https://1.1.1.1 -o /dev/null && echo ok"
fi

# ---------------------------------------------------------------------------
section "mtr --report — path data"
# ---------------------------------------------------------------------------

# mtr against loopback: 1 hop, 0% loss — a clean baseline.
MTR_OUT="$(mtr -nrwc 5 127.0.0.1 2>/dev/null)"
if [ -n "$MTR_OUT" ]; then
  pass "mtr -nrwc 5 127.0.0.1 returned output"

  # Loss column for loopback should be 0.0%
  LOSS_FIELD="$(printf '%s\n' "$MTR_OUT" | grep '127.0.0.1' | awk '{print $3}' | head -n1)"
  if [ "${LOSS_FIELD:-1}" = "0.0%" ] || [ "${LOSS_FIELD:-1}" = "0.0" ]; then
    pass "mtr reports 0.0% loss to 127.0.0.1"
  else
    warn "mtr reports ${LOSS_FIELD:-unknown} loss to 127.0.0.1 (expected 0.0%)"
  fi
else
  fail "mtr returned no output — mtr-tiny may not be installed"
fi

# mtr against gateway (if present)
if [ -n "$GW" ]; then
  GW_MTR="$(mtr -nrwc 3 "$GW" 2>/dev/null)"
  if [ -n "$GW_MTR" ]; then
    pass "mtr -nrwc 3 $GW returned output"
    GW_LOSS="$(printf '%s\n' "$GW_MTR" | grep "$GW" | awk '{print $3}' | head -n1)"
    if [ "${GW_LOSS:-1}" = "0.0%" ] || [ "${GW_LOSS:-1}" = "0.0" ]; then
      pass "mtr reports 0.0% loss to gateway $GW"
    else
      warn "mtr reports ${GW_LOSS:-unknown} loss to gateway (may be ICMP rate limiting)"
    fi
  else
    warn "mtr returned no output for gateway $GW"
  fi
fi

finish
