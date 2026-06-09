#!/usr/bin/env bash
# test-lab-5-trunk.sh — verify a built Lab 5 (two VLAN bridges joined by a trunk).
#
# VERIFY-ONLY and NON-DESTRUCTIVE. Auto-discovers two VLAN-filtering bridges, the
# trunk port between them (a bridge port carrying >=2 VLANs), and the host groups
# by subnet/VLAN. Then checks:
#   1. same-VLAN hosts reach each other across the trunk, and the trunk carries
#      that traffic *tagged* (tcpdump -e on the trunk shows an 802.1Q tag),
#   2. the two VLANs ride the trunk under DIFFERENT tags (the tag segregates them),
#   3. cross-VLAN hosts are isolated (a VLAN-A host cannot reach a VLAN-B host).
#
# Exit: 0 all passed, 1 any failed, 2 setup error.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"

require_cmds ip jq bridge tcpdump ping timeout awk grep

# ---------------------------------------------------------------------------
# Discover: two VLAN bridges, the trunk port, and host groups per VLAN
# ---------------------------------------------------------------------------
section "Discovering topology"

mapfile -t NAMESPACES < <(ns_list)
info "namespaces present: ${NAMESPACES[*]:-none}"

# Which namespaces hold a bridge (so we can exclude them from host grouping)?
declare -A IS_BRIDGE_NS
vlan_bridges=0
TRUNK_NS=""; TRUNK_BR=""; TRUNK_PORT=""
for ns in "${NAMESPACES[@]:-}"; do
  while IFS= read -r br; do
    [ -n "$br" ] || continue
    IS_BRIDGE_NS["$ns"]=1
    [ "$(ns_vlan_filtering "$ns" "$br")" = "1" ] || continue
    vlan_bridges=$((vlan_bridges + 1))
    # a trunk port is enslaved to this bridge and carries >=2 VLANs
    if [ -z "$TRUNK_PORT" ]; then
      while IFS= read -r port; do
        [ -n "$port" ] || continue
        if [ "$(port_vlans "$ns" "$port" | grep -c .)" -ge 2 ]; then
          TRUNK_NS="$ns"; TRUNK_BR="$br"; TRUNK_PORT="$port"; break
        fi
      done < <(ns_bridge_ports "$ns" "$br")
    fi
  done < <(ns_bridges "$ns")
done

if [ "$vlan_bridges" -lt 2 ]; then
  fail "expected >=2 VLAN-filtering bridges (two switches); found $vlan_bridges"
  finish
fi
if [ -z "$TRUNK_PORT" ]; then
  fail "no trunk port found (a bridge port carrying >=2 VLANs)"
  finish
fi

# Group host namespaces (non-bridge) by connected subnet.
declare -A SUB_HOSTS
for ns in "${NAMESPACES[@]}"; do
  [ -n "${IS_BRIDGE_NS[$ns]:-}" ] && continue
  while read -r sub dev ip; do
    [ -n "$sub" ] || continue
    SUB_HOSTS["$sub"]="${SUB_HOSTS[$sub]:-} $ns=$ip"
  done < <(ns_connected_v4 "$ns")
done

# Keep subnets that have >=2 hosts (a VLAN that spans both switches).
declare -a VLAN_SUBS
for sub in "${!SUB_HOSTS[@]}"; do
  # shellcheck disable=SC2086  # intentional word-split of the token list
  set -- ${SUB_HOSTS[$sub]}
  [ "$#" -ge 2 ] && VLAN_SUBS+=("$sub")
done

if [ "${#VLAN_SUBS[@]}" -lt 2 ]; then
  fail "expected >=2 VLANs each with >=2 hosts; found ${#VLAN_SUBS[@]} qualifying subnet(s)"
  finish
fi

# Take two VLAN groups (A and B) and pull two hosts from each.
read -r A_H0 A_H1 _ <<<"${SUB_HOSTS[${VLAN_SUBS[0]}]}"
read -r B_H0 B_H1 _ <<<"${SUB_HOSTS[${VLAN_SUBS[1]}]}"
A_SUB="${VLAN_SUBS[0]}"; B_SUB="${VLAN_SUBS[1]}"
A0_NS="${A_H0%=*}"; A0_IP="${A_H0#*=}"; A1_NS="${A_H1%=*}"; A1_IP="${A_H1#*=}"
B0_NS="${B_H0%=*}"; B0_IP="${B_H0#*=}"; B1_NS="${B_H1%=*}"; B1_IP="${B_H1#*=}"

pass "detected trunk '$TRUNK_PORT' (bridge '$TRUNK_BR' in '$TRUNK_NS') carrying $(port_vlans "$TRUNK_NS" "$TRUNK_PORT" | paste -sd, -)"
info "  VLAN A ($A_SUB): '$A0_NS' ($A0_IP) and '$A1_NS' ($A1_IP)"
info "  VLAN B ($B_SUB): '$B0_NS' ($B0_IP) and '$B1_NS' ($B1_IP)"

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------
section "Checks"

# Capture on the trunk while pinging a same-VLAN peer; sets RC / TAGGED / VID.
run_vlan_trunk_test() {
  local src="$1" dst="$2" cap="$3"
  ip netns exec "$src" ping -c 1 -W 1 -n "$dst" >/dev/null 2>&1 || true   # warm ARP/fdb
  tcpdump_start "$TRUNK_NS" "$TRUNK_PORT" "$cap" 8 "-e"; local pid="$_LAST_TCPDUMP_PID"
  sleep 1
  ip netns exec "$src" ping -c 3 -W 1 -n "$dst" >/dev/null 2>&1; RC=$?
  sleep 1
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  TAGGED="$(tcpdump_tagged_icmp_count "$cap")"
  VID="$(tcpdump_first_vlan "$cap")"
}

# 1. VLAN A across the trunk
run_vlan_trunk_test "$A0_NS" "$A1_IP" "$_WORKDIR/vlanA.txt"
rcA="$RC"; taggedA="$TAGGED"; vidA="$VID"
if [ "$rcA" -eq 0 ]; then
  pass "same-VLAN reachability (A): '$A0_NS' -> '$A1_NS' across the trunk"
else
  fail "same-VLAN reachability (A): '$A0_NS' cannot reach '$A1_NS' ($A1_IP)"
fi
if [ "$taggedA" -ge 1 ]; then
  pass "trunk carries VLAN A tagged (802.1Q vlan ${vidA:-?}, $taggedA ICMP frames)"
else
  fail "trunk showed no 802.1Q-tagged ICMP for VLAN A — traffic may not be crossing the trunk"
fi

# 2. VLAN B across the trunk
run_vlan_trunk_test "$B0_NS" "$B1_IP" "$_WORKDIR/vlanB.txt"
rcB="$RC"; taggedB="$TAGGED"; vidB="$VID"
if [ "$rcB" -eq 0 ]; then
  pass "same-VLAN reachability (B): '$B0_NS' -> '$B1_NS' across the trunk"
else
  fail "same-VLAN reachability (B): '$B0_NS' cannot reach '$B1_NS' ($B1_IP)"
fi
if [ "$taggedB" -ge 1 ]; then
  pass "trunk carries VLAN B tagged (802.1Q vlan ${vidB:-?}, $taggedB ICMP frames)"
else
  fail "trunk showed no 802.1Q-tagged ICMP for VLAN B"
fi

# 3. the two VLANs ride the trunk under different tags
if [ -n "$vidA" ] && [ -n "$vidB" ] && [ "$vidA" != "$vidB" ]; then
  pass "the two VLANs use different tags on the trunk (A=vlan $vidA, B=vlan $vidB) — the tag segregates them"
else
  fail "could not confirm distinct VLAN tags on the trunk (A='${vidA:-none}', B='${vidB:-none}')"
fi

# 4. cross-VLAN isolation: a VLAN-A host must NOT reach a VLAN-B host
if ip netns exec "$A0_NS" ping -c 2 -W 1 -n "$B0_IP" >/dev/null 2>&1; then
  fail "cross-VLAN isolation broken: '$A0_NS' reached '$B0_NS' ($B0_IP) across VLANs"
else
  pass "cross-VLAN isolation: '$A0_NS' cannot reach '$B0_NS' ($B0_IP) — VLANs stay separate"
fi

finish
