#!/usr/bin/env bash
# test-lab-2-switch.sh — verify a built Lab 2 (bridge with host ports) topology.
#
# VERIFY-ONLY and NON-DESTRUCTIVE. Run after building Lab 2 in the workbench.
# Auto-discovers the bridge namespace and the host namespaces (by shared subnet),
# then checks the lab's objective:
#   1. same-subnet hosts reach each other over the bridge (pure L2),
#   2. and the bridge learned their MACs (the "show mac address-table" mechanism) —
#      proving the traffic was switched, not delivered some other way.
#
# Exit: 0 all passed, 1 any failed, 2 setup error.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"

require_cmds ip jq bridge tcpdump ping timeout awk grep

# ---------------------------------------------------------------------------
# Discover: a bridge namespace + the host namespaces sharing one subnet
# ---------------------------------------------------------------------------
section "Discovering topology"

mapfile -t NAMESPACES < <(ns_list)
info "namespaces present: ${NAMESPACES[*]:-none}"

# bridge ns = a namespace holding a bridge device with >=2 enslaved ports.
BRIDGE_NS=""; BR=""
for ns in "${NAMESPACES[@]:-}"; do
  while IFS= read -r br; do
    [ -n "$br" ] || continue
    n_ports="$(ns_bridge_ports "$ns" "$br" | grep -c .)"
    if [ "$n_ports" -ge 2 ]; then BRIDGE_NS="$ns"; BR="$br"; break; fi
  done < <(ns_bridges "$ns")
  [ -n "$BRIDGE_NS" ] && break
done

if [ -z "$BRIDGE_NS" ]; then
  fail "no namespace with a bridge that has >=2 enslaved ports was found"
  finish
fi

# host namespaces grouped by connected subnet (excluding the bridge ns).
# Pick the subnet shared by the most namespaces (>=2) — that's the lab's LAN.
declare -A SUBNET_COUNT
for ns in "${NAMESPACES[@]}"; do
  [ "$ns" = "$BRIDGE_NS" ] && continue
  while read -r sub dev ip; do
    [ -n "$sub" ] || continue
    SUBNET_COUNT["$sub"]=$(( ${SUBNET_COUNT["$sub"]:-0} + 1 ))
  done < <(ns_connected_v4 "$ns")
done

LAN=""; best=0
for sub in "${!SUBNET_COUNT[@]}"; do
  if [ "${SUBNET_COUNT[$sub]}" -gt "$best" ]; then best="${SUBNET_COUNT[$sub]}"; LAN="$sub"; fi
done

if [ -z "$LAN" ] || [ "$best" -lt 2 ]; then
  fail "could not find >=2 host namespaces sharing a subnet behind bridge '$BR' in '$BRIDGE_NS'"
  finish
fi

# collect the hosts on that subnet: name, dev, ip, mac
declare -a H_NS H_DEV H_IP H_MAC
for ns in "${NAMESPACES[@]}"; do
  [ "$ns" = "$BRIDGE_NS" ] && continue
  while read -r sub dev ip; do
    if [ "$sub" = "$LAN" ]; then
      H_NS+=("$ns"); H_DEV+=("$dev"); H_IP+=("$ip"); H_MAC+=("$(ns_iface_mac "$ns" "$dev")")
      break
    fi
  done < <(ns_connected_v4 "$ns")
done

pass "detected bridge '$BR' in '$BRIDGE_NS' with ${#H_NS[@]} hosts on $LAN"
for i in "${!H_NS[@]}"; do
  info "  host '${H_NS[$i]}'  ${H_IP[$i]}  (${H_DEV[$i]}, mac ${H_MAC[$i]})"
done

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------
section "Checks"

# 1. same-subnet L2 reachability from host[0] to every other host.
src_ns="${H_NS[0]}"; src_ip="${H_IP[0]}"
for i in "${!H_NS[@]}"; do
  [ "$i" -eq 0 ] && continue
  dst_ns="${H_NS[$i]}"; dst_ip="${H_IP[$i]}"
  if ip netns exec "$src_ns" ping -c 2 -W 1 -n "$dst_ip" >/dev/null 2>&1; then
    pass "L2 reachability: '$src_ns' -> '$dst_ns' ($dst_ip)"
  else
    fail "L2 reachability: '$src_ns' cannot reach '$dst_ns' ($dst_ip) on the same subnet"
  fi
done

# 2. mechanism: the bridge must have learned the hosts' MACs on its ports.
#    (Generate a little traffic first so learning is fresh, then read the fdb.)
ip netns exec "$src_ns" ping -c 1 -W 1 -n "${H_IP[1]}" >/dev/null 2>&1 || true
learned=0; checked=0
for i in "${!H_NS[@]}"; do
  mac="${H_MAC[$i]}"; [ -n "$mac" ] || continue
  checked=$((checked + 1))
  if fdb_has_mac "$BRIDGE_NS" "$BR" "$mac"; then
    learned=$((learned + 1))
  else
    info "  MAC $mac (${H_NS[$i]}) not yet in '$BR' fdb"
  fi
done
if [ "$checked" -gt 0 ] && [ "$learned" -eq "$checked" ]; then
  pass "MAC learning: bridge '$BR' learned all $checked host MACs on its ports (switched, not shortcut)"
else
  fail "MAC learning: bridge '$BR' learned only $learned/$checked host MACs on its ports — a host isn't switching through the bridge"
fi

finish
