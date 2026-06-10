#!/usr/bin/env bash
# test-lab-5-bfd.sh — verify Lab A04-5 (BFD-accelerated failover).
#
# Checks that:
#   - At least one BFD peer is in Up state (objective)
#   - The configured transmit interval is <= 300ms (sub-second detection possible)
#   - BGP or OSPF sessions reference the BFD peer (mechanism — they are wired together)
#
# NOTE: This checker does NOT flap any links. The failover timing exercise
# (measuring BGP reconvergence with vs without BFD) is a reader exercise in
# the walkthrough; automated flapping would violate the non-destructive rule.
#
# VERIFY-ONLY / NON-DESTRUCTIVE.
#
# Run:  ./tests/routing/test.sh 5

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

require_cmds ip jq vtysh

# ---------------------------------------------------------------------------
# Discover topology
# ---------------------------------------------------------------------------
section "Topology discovery"

BFD_NS=()
for ns in $(ns_list); do
    frr_socket_ready "$ns" || continue
    if frr_bfd_peer_up "$ns"; then
        BFD_NS+=("$ns")
    fi
done

if [ "${#BFD_NS[@]}" -eq 0 ]; then
    # Provide diagnostics
    for ns in $(ns_list); do
        frr_socket_ready "$ns" || continue
        bfd_count=$(frr_bfd_peer_count "$ns")
        if [ "${bfd_count:-0}" -gt 0 ]; then
            info "frr@$ns: $bfd_count BFD peer(s) found but none Up yet"
            ip netns exec "$ns" vtysh -N "$ns" -c 'show bfd peers' 2>/dev/null | \
                while IFS= read -r line; do info "  $line"; done || true
        fi
    done
    die "No namespace has a BFD peer in Up state. Add 'bfd' to a BGP/OSPF neighbor and complete Lab 5."
fi

info "Namespaces with BFD Up: ${BFD_NS[*]}"

# ---------------------------------------------------------------------------
# Part A — BFD peer is Up (objective)
# ---------------------------------------------------------------------------
section "Part A — BFD peer is Up"

for ns in "${BFD_NS[@]}"; do
    peer_count=$(frr_bfd_peer_count "$ns")
    pass "frr@$ns: $peer_count BFD peer(s), at least one Up"
    ip netns exec "$ns" vtysh -N "$ns" -c 'show bfd peers' 2>/dev/null | \
        grep -E '(peer|status|tx-interval|rx-interval|detect-mult)' | \
        while IFS= read -r line; do info "  $line"; done || true
done

# ---------------------------------------------------------------------------
# Part B — Sub-second transmit interval configured (mechanism)
# ---------------------------------------------------------------------------
section "Part B — BFD transmit interval <= 300ms"

for ns in "${BFD_NS[@]}"; do
    interval_ms=$(frr_bfd_interval_ms "$ns")
    if [ "${interval_ms:-300}" -le 300 ]; then
        pass "frr@$ns: BFD TX interval is ${interval_ms}ms (<= 300ms — sub-second detection possible)"
    else
        fail "frr@$ns: BFD TX interval is ${interval_ms}ms (> 300ms — tighten the interval: 'transmit-interval 100')"
    fi
done

# ---------------------------------------------------------------------------
# Part C — BGP or OSPF session references BFD (mechanism — wired together)
# ---------------------------------------------------------------------------
section "Part C — BGP/OSPF sessions reference BFD"

for ns in "${BFD_NS[@]}"; do
    # Check BGP neighbor config for bfd keyword
    bgp_bfd=$(ip netns exec "$ns" vtysh -N "$ns" -c 'show running-config' 2>/dev/null | \
              grep -c 'bfd$' 2>/dev/null || echo 0)
    # Check OSPF for bfd keyword
    ospf_bfd=$(ip netns exec "$ns" vtysh -N "$ns" -c 'show running-config' 2>/dev/null | \
               grep -c 'ip ospf bfd' 2>/dev/null || echo 0)

    if [ "${bgp_bfd:-0}" -gt 0 ] || [ "${ospf_bfd:-0}" -gt 0 ]; then
        pass "frr@$ns: routing session(s) reference BFD (bgp_bfd=$bgp_bfd ospf_bfd=$ospf_bfd)"
    else
        fail "frr@$ns: BFD peers Up but no BGP/OSPF neighbor references BFD — add 'neighbor <x> bfd'"
    fi
done

finish
