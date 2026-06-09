#!/usr/bin/env bash
# test-lab-2-ospf.sh — verify Lab A04-2 (first OSPF adjacency).
#
# Checks that:
#   - At least one OSPF adjacency is in Full state (objective)
#   - The peer's loopback route appears in the kernel FIB with proto=ospf (mechanism)
#   - The route is reachable via ping (end-to-end objective)
#
# VERIFY-ONLY / NON-DESTRUCTIVE.  Auto-discovers: the namespace that has an
# OSPF neighbor in Full state is the router under test.
#
# Run:  ./tests/routing/test.sh 2

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

require_cmds ip jq vtysh ping

# ---------------------------------------------------------------------------
# Discover topology
# ---------------------------------------------------------------------------
section "Topology discovery"

OSPF_NS=()
for ns in $(ns_list); do
    frr_socket_ready "$ns" || continue
    if frr_ospf_any_full "$ns"; then
        OSPF_NS+=("$ns")
    fi
done

if [ "${#OSPF_NS[@]}" -eq 0 ]; then
    # Maybe OSPF is configured but not yet Full — give useful info
    for ns in $(ns_list); do
        frr_socket_ready "$ns" || continue
        count=$(frr_ospf_neighbor_count "$ns")
        if [ "${count:-0}" -gt 0 ]; then
            info "frr@$ns: $count OSPF neighbor(s) found but none in Full state yet"
            ip netns exec "$ns" vtysh -N "$ns" -c 'show ip ospf neighbor' 2>/dev/null || true
        fi
    done
    die "No namespace has an OSPF neighbor in Full state. Complete Lab 2 first."
fi

info "Namespaces with Full OSPF neighbors: ${OSPF_NS[*]}"

# ---------------------------------------------------------------------------
# Part A — Adjacency state
# ---------------------------------------------------------------------------
section "Part A — OSPF adjacency is Full"

for ns in "${OSPF_NS[@]}"; do
    nbr_count=$(frr_ospf_neighbor_count "$ns")
    pass "frr@$ns: $nbr_count OSPF neighbor(s) with at least one in Full state"

    # Show neighbor table for reference
    ip netns exec "$ns" vtysh -N "$ns" -c 'show ip ospf neighbor' 2>/dev/null | \
        grep -v '^$' | while IFS= read -r line; do info "  $line"; done || true
done

# ---------------------------------------------------------------------------
# Part B — OSPF routes in kernel FIB (mechanism)
# ---------------------------------------------------------------------------
section "Part B — OSPF routes promoted to kernel FIB"

for ns in "${OSPF_NS[@]}"; do
    ospf_routes=$(ip -j -n "$ns" route show proto ospf 2>/dev/null | jq 'length' 2>/dev/null || echo 0)
    if [ "${ospf_routes:-0}" -gt 0 ]; then
        pass "frr@$ns: $ospf_routes OSPF route(s) in kernel FIB (proto ospf)"
        ip -n "$ns" route show proto ospf 2>/dev/null | \
            while IFS= read -r line; do info "  $line"; done || true
    else
        fail "frr@$ns: no routes with proto=ospf in kernel FIB — OSPF adjacency Full but routes not installed?"
    fi
done

# ---------------------------------------------------------------------------
# Part C — Loopback reachability via OSPF (end-to-end objective)
# ---------------------------------------------------------------------------
section "Part C — Loopback reachability via OSPF"

for ns in "${OSPF_NS[@]}"; do
    # Find OSPF-learned loopback routes (/32s with proto=ospf)
    loopbacks=()
    while IFS= read -r prefix; do
        [ -n "$prefix" ] && loopbacks+=("$prefix")
    done < <(ip -j -n "$ns" route show proto ospf 2>/dev/null | \
             jq -r '.[] | select(.dst | test("/32$")) | .dst' 2>/dev/null)

    if [ "${#loopbacks[@]}" -eq 0 ]; then
        info "frr@$ns: no /32 OSPF routes found (loopbacks may not be advertised yet)"
        continue
    fi

    for lo_prefix in "${loopbacks[@]}"; do
        lo_ip="${lo_prefix%/*}"
        if ping_ok "$ns" "$lo_ip" 3; then
            pass "frr@$ns: ping to OSPF-learned loopback $lo_ip succeeded"
        else
            fail "frr@$ns: ping to OSPF-learned loopback $lo_ip failed"
        fi
    done
done

finish
