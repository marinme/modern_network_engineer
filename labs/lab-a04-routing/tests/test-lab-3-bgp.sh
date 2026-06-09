#!/usr/bin/env bash
# test-lab-3-bgp.sh — verify Lab A04-3 (first BGP session, numbered eBGP).
#
# Checks that:
#   - At least one BGP session is in Established state (objective)
#   - The peer's loopback prefix appears in FIB as proto=bgp (mechanism)
#   - The route is reachable via ping (end-to-end objective)
#   - The session uses numbered (IP) peers, not interface-based (unnumbered)
#
# VERIFY-ONLY / NON-DESTRUCTIVE.
#
# Run:  ./tests/routing/test.sh 3

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

require_cmds ip jq vtysh ping

# ---------------------------------------------------------------------------
# Discover topology
# ---------------------------------------------------------------------------
section "Topology discovery"

BGP_NS=()
for ns in $(ns_list); do
    frr_socket_ready "$ns" || continue
    if frr_bgp_any_established "$ns"; then
        BGP_NS+=("$ns")
    fi
done

if [ "${#BGP_NS[@]}" -eq 0 ]; then
    for ns in $(ns_list); do
        frr_socket_ready "$ns" || continue
        # Show BGP summary for context even if not Established
        summary=$(ip netns exec "$ns" vtysh -N "$ns" -c 'show ip bgp summary' 2>/dev/null)
        if [ -n "$summary" ]; then
            info "frr@$ns BGP summary:"
            echo "$summary" | grep -v '^$' | head -20 | while IFS= read -r line; do info "  $line"; done || true
        fi
    done
    die "No namespace has an Established BGP session. Complete Lab 3 first."
fi

info "Namespaces with Established BGP: ${BGP_NS[*]}"

# ---------------------------------------------------------------------------
# Part A — BGP session is Established
# ---------------------------------------------------------------------------
section "Part A — BGP session Established"

for ns in "${BGP_NS[@]}"; do
    # Count established peers
    est_count=$(ip netns exec "$ns" vtysh -N "$ns" -c 'show ip bgp summary json' 2>/dev/null | \
        jq '[.ipv4Unicast?.peers? // {} | to_entries[] | select(.value.state == "Established")] | length' \
        2>/dev/null || echo 0)
    pass "frr@$ns: $est_count BGP peer(s) in Established state"
    ip netns exec "$ns" vtysh -N "$ns" -c 'show ip bgp summary' 2>/dev/null | \
        grep -E '(Established|Neighbor|BGP)' | head -10 | \
        while IFS= read -r line; do info "  $line"; done || true
done

# ---------------------------------------------------------------------------
# Part B — BGP routes in kernel FIB (mechanism)
# ---------------------------------------------------------------------------
section "Part B — BGP prefixes promoted to kernel FIB (proto bgp)"

for ns in "${BGP_NS[@]}"; do
    bgp_routes=$(ip -j -n "$ns" route show proto bgp 2>/dev/null | jq 'length' 2>/dev/null || echo 0)
    if [ "${bgp_routes:-0}" -gt 0 ]; then
        pass "frr@$ns: $bgp_routes BGP route(s) in kernel FIB (proto bgp)"
        ip -n "$ns" route show proto bgp 2>/dev/null | \
            while IFS= read -r line; do info "  $line"; done || true
    else
        fail "frr@$ns: session Established but no routes in FIB with proto=bgp — advertise a prefix"
    fi
done

# ---------------------------------------------------------------------------
# Part C — Reachability to BGP-learned prefixes (end-to-end objective)
# ---------------------------------------------------------------------------
section "Part C — Reachability to BGP-learned prefixes"

for ns in "${BGP_NS[@]}"; do
    bgp_prefixes=()
    while IFS= read -r prefix; do
        [ -n "$prefix" ] && bgp_prefixes+=("$prefix")
    done < <(ip -j -n "$ns" route show proto bgp 2>/dev/null | \
             jq -r '.[].dst' 2>/dev/null)

    if [ "${#bgp_prefixes[@]}" -eq 0 ]; then
        info "frr@$ns: no BGP-learned prefixes to ping"
        continue
    fi

    for prefix in "${bgp_prefixes[@]}"; do
        dst_ip="${prefix%/*}"
        if ping_ok "$ns" "$dst_ip" 3; then
            pass "frr@$ns: ping to BGP-learned $prefix ($dst_ip) succeeded"
        else
            fail "frr@$ns: ping to BGP-learned $prefix ($dst_ip) failed"
        fi
    done
done

# ---------------------------------------------------------------------------
# Part D — Peer type is numbered (not unnumbered) — mechanism check
# ---------------------------------------------------------------------------
section "Part D — Peers are numbered (IP-based, not interface-based)"

for ns in "${BGP_NS[@]}"; do
    # Unnumbered peers have idType "interface"; numbered peers have an IP peerIp
    numbered=$(ip netns exec "$ns" vtysh -N "$ns" -c 'show ip bgp summary json' 2>/dev/null | \
        jq '[.ipv4Unicast?.peers? // {} | to_entries[] |
             select(.value.state == "Established" and (.value.idType? != "interface"))] | length' \
        2>/dev/null || echo 0)
    if [ "${numbered:-0}" -gt 0 ]; then
        pass "frr@$ns: $numbered numbered (IP-based) BGP peer(s) Established"
    else
        info "frr@$ns: all Established sessions are interface-based — if you ran Lab 4 already, this is expected"
    fi
done

finish
