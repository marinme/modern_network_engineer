#!/usr/bin/env bash
# test-lab-3-compose.sh — verify a built Lab 3 (host—switch—router—switch—host).
#
# VERIFY-ONLY and NON-DESTRUCTIVE. Auto-discovers the router (forwards + two
# subnets) and the hosts on each subnet, then checks:
#   1. same-subnet hosts reach each other on-link (L2 through a switch, NOT routed),
#   2. cross-subnet hosts reach each other via the router, proven by tcpdump on
#      BOTH router legs (so the path really crosses the router).
#
# Exit: 0 all passed, 1 any failed, 2 setup error.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"

require_cmds ip jq tcpdump ping timeout awk grep

# ---------------------------------------------------------------------------
# Discover: router (forwarding + 2 subnets) and the hosts on each subnet
# ---------------------------------------------------------------------------
section "Discovering topology"

mapfile -t NAMESPACES < <(ns_list)
info "namespaces present: ${NAMESPACES[*]:-none}"

ROUTER=""
A_SUB=""; A_DEV=""; A_GW=""; declare -a AH_NS AH_IP
B_SUB=""; B_DEV=""; B_GW=""; declare -a BH_NS BH_IP

for cand in "${NAMESPACES[@]:-}"; do
  [ "$(ns_forwarding "$cand")" = "1" ] || continue
  mapfile -t legs < <(ns_connected_v4 "$cand")
  [ "${#legs[@]}" -ge 2 ] || continue

  A_SUB=""; B_SUB=""; AH_NS=(); AH_IP=(); BH_NS=(); BH_IP=()
  for leg in "${legs[@]}"; do
    read -r sub dev gw <<<"$leg"
    declare -a hs_ns hs_ip; hs_ns=(); hs_ip=()
    for h in "${NAMESPACES[@]}"; do
      [ "$h" = "$cand" ] && continue
      hip="$(ns_ip_in_subnet "$h" "$sub")"
      [ -n "$hip" ] && { hs_ns+=("$h"); hs_ip+=("$hip"); }
    done
    [ "${#hs_ns[@]}" -ge 1 ] || continue
    if [ -z "$A_SUB" ]; then
      A_SUB="$sub"; A_DEV="$dev"; A_GW="$gw"; AH_NS=("${hs_ns[@]}"); AH_IP=("${hs_ip[@]}")
    elif [ -z "$B_SUB" ]; then
      B_SUB="$sub"; B_DEV="$dev"; B_GW="$gw"; BH_NS=("${hs_ns[@]}"); BH_IP=("${hs_ip[@]}")
      break
    fi
  done
  if [ -n "$A_SUB" ] && [ -n "$B_SUB" ]; then ROUTER="$cand"; break; fi
done

if [ -z "$ROUTER" ]; then
  fail "could not identify a forwarding router joining two host-bearing subnets"
  finish
fi

pass "detected router '$ROUTER' joining $A_SUB and $B_SUB"
info "  $A_SUB via $A_DEV (gw $A_GW): hosts ${AH_NS[*]}"
info "  $B_SUB via $B_DEV (gw $B_GW): hosts ${BH_NS[*]}"

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------
section "Checks"

# 1. forwarding
if [ "$(ns_forwarding "$ROUTER")" = "1" ]; then
  pass "router '$ROUTER' has net.ipv4.ip_forward = 1"
else
  fail "router '$ROUTER' net.ipv4.ip_forward is not 1"
fi

# 2. same-subnet reachability must be L2 (on-link), not via the router.
same_ns=""; same_dst_ns=""; same_dst_ip=""
if [ "${#AH_NS[@]}" -ge 2 ]; then
  same_ns="${AH_NS[0]}"; same_dst_ns="${AH_NS[1]}"; same_dst_ip="${AH_IP[1]}"
elif [ "${#BH_NS[@]}" -ge 2 ]; then
  same_ns="${BH_NS[0]}"; same_dst_ns="${BH_NS[1]}"; same_dst_ip="${BH_IP[1]}"
fi
if [ -n "$same_ns" ]; then
  if ip netns exec "$same_ns" ping -c 2 -W 1 -n "$same_dst_ip" >/dev/null 2>&1; then
    read -r gw _dev <<<"$(ns_route_nexthop "$same_ns" "$same_dst_ip")"
    if [ "$gw" = "-" ]; then
      pass "same-subnet '$same_ns' -> '$same_dst_ns' is on-link L2 (through the switch, not the router)"
    else
      fail "same-subnet '$same_ns' -> '$same_dst_ns' resolves via gateway $gw — expected on-link (L2)"
    fi
  else
    fail "same-subnet '$same_ns' cannot reach '$same_dst_ns' ($same_dst_ip)"
  fi
else
  warn "only one host per subnet found — skipping the same-subnet L2 check"
fi

# 3. cross-subnet reachability via the router (gateway + transit proof).
src_ns="${AH_NS[0]}"; dst_ns="${BH_NS[0]}"; dst_ip="${BH_IP[0]}"
read -r xgw _xdev <<<"$(ns_route_nexthop "$src_ns" "$dst_ip")"
if [ "$xgw" = "$A_GW" ]; then
  pass "cross-subnet '$src_ns' routes to '$dst_ns' via the router ($xgw)"
else
  fail "cross-subnet '$src_ns' should route to '$dst_ns' via $A_GW; resolver says gateway=$xgw"
fi
if ip netns exec "$src_ns" ping -c 3 -W 1 -n "$dst_ip" >/dev/null 2>&1; then
  pass "cross-subnet reachability: '$src_ns' -> '$dst_ns' ($dst_ip)"
else
  fail "cross-subnet reachability: '$src_ns' cannot reach '$dst_ns' ($dst_ip)"
fi

section "Mechanism: cross-subnet traffic must transit the router"
capA="$_WORKDIR/legA.txt"; capB="$_WORKDIR/legB.txt"
tcpdump_start "$ROUTER" "$A_DEV" "$capA" 8; pidA="$_LAST_TCPDUMP_PID"
tcpdump_start "$ROUTER" "$B_DEV" "$capB" 8; pidB="$_LAST_TCPDUMP_PID"
sleep 1
ip netns exec "$src_ns" ping -c 3 -W 1 -n "$dst_ip" >/dev/null 2>&1
sleep 1
kill "$pidA" "$pidB" 2>/dev/null || true
wait "$pidA" "$pidB" 2>/dev/null || true
nA="$(tcpdump_icmp_count "$capA")"; nB="$(tcpdump_icmp_count "$capB")"
if [ "$nA" -ge 1 ] && [ "$nB" -ge 1 ]; then
  pass "ICMP seen on both router legs ($A_DEV=$nA, $B_DEV=$nB) — traffic transits '$ROUTER'"
else
  fail "ICMP not seen on both legs ($A_DEV=$nA, $B_DEV=$nB) — traffic did not cross the router"
fi

finish
