#!/usr/bin/env bash
# test-lab-4-svi.sh — verify a built Lab 4 (VLAN-aware bridge with SVIs).
#
# VERIFY-ONLY and NON-DESTRUCTIVE. Auto-discovers the layer-3 switch: a single
# namespace that forwards and has two connected subnets reached through *VLAN
# interfaces* (the SVIs) on a VLAN-filtering bridge. Then checks:
#   1. it really is an SVI setup (vlan-filtering bridge + vlan-type legs),
#   2. same-VLAN hosts reach each other on-link (L2, not routed),
#   3. inter-VLAN hosts reach each other via the SVIs, proven by tcpdump on BOTH
#      SVIs (so the bridge routed between VLANs rather than some shortcut).
#
# Exit: 0 all passed, 1 any failed, 2 setup error.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"

require_cmds ip jq tcpdump ping timeout awk grep

# ---------------------------------------------------------------------------
# Discover: a forwarding ns whose two subnets are reached via SVIs
# ---------------------------------------------------------------------------
section "Discovering topology"

mapfile -t NAMESPACES < <(ns_list)
info "namespaces present: ${NAMESPACES[*]:-none}"

SW=""
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
  if [ -n "$A_SUB" ] && [ -n "$B_SUB" ]; then SW="$cand"; break; fi
done

if [ -z "$SW" ]; then
  fail "could not identify a forwarding namespace joining two host-bearing subnets"
  finish
fi

pass "detected layer-3 switch '$SW' joining $A_SUB and $B_SUB"
info "  $A_SUB via $A_DEV (gw $A_GW): hosts ${AH_NS[*]}"
info "  $B_SUB via $B_DEV (gw $B_GW): hosts ${BH_NS[*]}"

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------
section "Checks"

# 1. it's genuinely an SVI setup: a vlan-filtering bridge + vlan-type legs.
vbridge=""
while IFS= read -r br; do
  [ -n "$br" ] || continue
  if [ "$(ns_vlan_filtering "$SW" "$br")" = "1" ]; then vbridge="$br"; break; fi
done < <(ns_bridges "$SW")
if [ -n "$vbridge" ]; then
  pass "VLAN-aware bridge present: '$vbridge' has vlan_filtering=1"
else
  fail "no VLAN-filtering bridge found in '$SW' (Lab 4 needs 'bridge ... vlan_filtering 1')"
fi

kindA="$(ns_iface_kind "$SW" "$A_DEV")"; kindB="$(ns_iface_kind "$SW" "$B_DEV")"
if [ "$kindA" = "vlan" ] && [ "$kindB" = "vlan" ]; then
  pass "both gateways are SVIs (VLAN interfaces): $A_DEV, $B_DEV"
else
  fail "expected the two gateways to be VLAN interfaces (SVIs); got $A_DEV=$kindA, $B_DEV=$kindB"
fi

# 2. same-VLAN reachability must be on-link L2 (not via an SVI).
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
      pass "same-VLAN '$same_ns' -> '$same_dst_ns' is on-link L2 (no routing)"
    else
      fail "same-VLAN '$same_ns' -> '$same_dst_ns' resolves via $gw — expected on-link (L2)"
    fi
  else
    fail "same-VLAN '$same_ns' cannot reach '$same_dst_ns' ($same_dst_ip)"
  fi
else
  warn "only one host per VLAN found — skipping the same-VLAN L2 check"
fi

# 3. inter-VLAN reachability routed via the SVIs (gateway + transit on both SVIs).
src_ns="${AH_NS[0]}"; dst_ns="${BH_NS[0]}"; dst_ip="${BH_IP[0]}"
read -r xgw _xdev <<<"$(ns_route_nexthop "$src_ns" "$dst_ip")"
if [ "$xgw" = "$A_GW" ]; then
  pass "inter-VLAN '$src_ns' routes to '$dst_ns' via the SVI gateway ($xgw)"
else
  fail "inter-VLAN '$src_ns' should route to '$dst_ns' via $A_GW; resolver says gateway=$xgw"
fi
if ip netns exec "$src_ns" ping -c 3 -W 1 -n "$dst_ip" >/dev/null 2>&1; then
  pass "inter-VLAN reachability: '$src_ns' -> '$dst_ns' ($dst_ip)"
else
  fail "inter-VLAN reachability: '$src_ns' cannot reach '$dst_ns' ($dst_ip)"
fi

section "Mechanism: inter-VLAN traffic must be routed through the SVIs"
capA="$_WORKDIR/sviA.txt"; capB="$_WORKDIR/sviB.txt"
tcpdump_start "$SW" "$A_DEV" "$capA" 8; pidA="$_LAST_TCPDUMP_PID"
tcpdump_start "$SW" "$B_DEV" "$capB" 8; pidB="$_LAST_TCPDUMP_PID"
sleep 1
ip netns exec "$src_ns" ping -c 3 -W 1 -n "$dst_ip" >/dev/null 2>&1
sleep 1
kill "$pidA" "$pidB" 2>/dev/null || true
wait "$pidA" "$pidB" 2>/dev/null || true
nA="$(tcpdump_icmp_count "$capA")"; nB="$(tcpdump_icmp_count "$capB")"
if [ "$nA" -ge 1 ] && [ "$nB" -ge 1 ]; then
  pass "ICMP seen on both SVIs ($A_DEV=$nA, $B_DEV=$nB) — '$SW' routed between the VLANs"
else
  fail "ICMP not seen on both SVIs ($A_DEV=$nA, $B_DEV=$nB) — inter-VLAN routing did not happen as expected"
fi

finish
