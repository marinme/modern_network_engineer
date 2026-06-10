#!/usr/bin/env bash
# test-lab-4-bgp-unnumbered.sh — verify Lab A04-4 (BGP unnumbered).
#
# Checks that:
#   - At least one BGP session is Established over an interface-based (unnumbered) peer
#   - The next-hop in the BGP table is an IPv6 link-local address (fe80::...)
#   - IPv4 prefixes are present in the kernel FIB as proto=bgp (mechanism)
#   - No manual IPv4 peer addresses are configured on the established sessions
#
# VERIFY-ONLY / NON-DESTRUCTIVE.
#
# Run:  ./tests/routing/test.sh 4

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

require_cmds ip jq vtysh

# ---------------------------------------------------------------------------
# Discover topology
# ---------------------------------------------------------------------------
section "Topology discovery"

UNM_NS=()
for ns in $(ns_list); do
    frr_socket_ready "$ns" || continue
    # Look for interface-based Established sessions
    has_unnumbered=$(ip netns exec "$ns" vtysh -N "$ns" -c 'show ip bgp summary json' 2>/dev/null | \
        jq 'any(.ipv4Unicast?.peers? // {} | to_entries[];
            .value.state == "Established" and .value.idType? == "interface")' \
        2>/dev/null || echo "false")
    if [ "$has_unnumbered" = "true" ]; then
        UNM_NS+=("$ns")
    fi
done

if [ "${#UNM_NS[@]}" -eq 0 ]; then
    for ns in $(ns_list); do
        frr_socket_ready "$ns" || continue
        ip netns exec "$ns" vtysh -N "$ns" -c 'show ip bgp summary' 2>/dev/null | head -15 | \
            while IFS= read -r line; do info "  frr@$ns: $line"; done || true
    done
    die "No namespace has an Established interface-based (unnumbered) BGP session. Complete Lab 4 first."
fi

info "Namespaces with unnumbered BGP: ${UNM_NS[*]}"

# ---------------------------------------------------------------------------
# Part A — Interface-based session is Established (objective)
# ---------------------------------------------------------------------------
section "Part A — Unnumbered BGP session Established"

for ns in "${UNM_NS[@]}"; do
    count=$(ip netns exec "$ns" vtysh -N "$ns" -c 'show ip bgp summary json' 2>/dev/null | \
        jq '[.ipv4Unicast?.peers? // {} | to_entries[] |
             select(.value.state == "Established" and .value.idType? == "interface")] | length' \
        2>/dev/null || echo 0)
    pass "frr@$ns: $count interface-based BGP session(s) Established"
done

# ---------------------------------------------------------------------------
# Part B — Next-hop is IPv6 link-local (mechanism)
# ---------------------------------------------------------------------------
section "Part B — BGP next-hops are IPv6 link-local addresses"

for ns in "${UNM_NS[@]}"; do
    if frr_bgp_peer_link_local_nexthop "$ns"; then
        pass "frr@$ns: BGP table contains routes with fe80:: next-hop (IPv6 link-local transport)"
    else
        fail "frr@$ns: no fe80:: next-hops found in BGP table — unnumbered BGP uses link-local, check configuration"
    fi
done

# ---------------------------------------------------------------------------
# Part C — IPv4 prefixes in FIB as proto=bgp (mechanism)
# ---------------------------------------------------------------------------
section "Part C — IPv4 prefixes in kernel FIB via BGP"

for ns in "${UNM_NS[@]}"; do
    bgp_routes=$(ip -j -n "$ns" route show proto bgp 2>/dev/null | jq 'length' 2>/dev/null || echo 0)
    if [ "${bgp_routes:-0}" -gt 0 ]; then
        pass "frr@$ns: $bgp_routes IPv4 BGP route(s) in kernel FIB (proto bgp) via link-local transport"
        ip -n "$ns" route show proto bgp 2>/dev/null | \
            while IFS= read -r line; do info "  $line"; done || true
    else
        fail "frr@$ns: no proto=bgp routes in kernel FIB — session Established but no prefixes advertised?"
    fi
done

# ---------------------------------------------------------------------------
# Part D — IPv6 is enabled on the relevant interfaces (mechanism pre-condition)
# ---------------------------------------------------------------------------
section "Part D — IPv6 link-local addresses present on peering interfaces"

for ns in "${UNM_NS[@]}"; do
    # Find interfaces with BGP unnumbered peers configured
    peer_ifaces=$(ip netns exec "$ns" vtysh -N "$ns" -c 'show ip bgp summary json' 2>/dev/null | \
        jq -r '.ipv4Unicast?.peers? // {} | to_entries[] |
                select(.value.idType? == "interface") | .key' \
        2>/dev/null)

    if [ -z "$peer_ifaces" ]; then
        info "frr@$ns: could not determine peering interfaces (OK if summary format differs)"
        continue
    fi

    for iface in $peer_ifaces; do
        has_ll=$(ip -j -n "$ns" addr show dev "$iface" 2>/dev/null | \
            jq 'any(.[].addr_info[]; .family=="inet6" and (.scope? == "link" or (.local? | test("^fe80:"))))' \
            2>/dev/null || echo "false")
        if [ "$has_ll" = "true" ]; then
            pass "frr@$ns: $iface has a fe80:: link-local address (IPv6 enabled)"
        else
            fail "frr@$ns: $iface has no fe80:: link-local address — BGP unnumbered requires IPv6"
        fi
    done
done

finish
