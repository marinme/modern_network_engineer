#!/usr/bin/env bash
# test-lab-4-bonding.sh — verify Lab A03-4 (Linux bonding: active-backup + LACP).
#
# Auto-discovers: any namespace that has a bond interface.
# Checks: mode, active slave present, (for LACP) partner MAC non-zero.
#
# Run:  ./tests/test.sh 4

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

require_cmds ip jq

# ---------------------------------------------------------------------------
# Auto-discover
# ---------------------------------------------------------------------------
section "Topology discovery"

declare -A BOND_NS=()   # bond_iface → ns

for ns in $(ns_list); do
    bonds=$(ip -j -n "$ns" link show type bond 2>/dev/null | jq -r '.[].ifname' 2>/dev/null)
    while IFS= read -r b; do
        [ -n "$b" ] && BOND_NS["$b"]="$ns"
    done <<< "$bonds"
done

[ "${#BOND_NS[@]}" -ge 1 ] || \
    die "No bond interfaces found. Build the topology first (lab-4-bonding.md)."

info "Found ${#BOND_NS[@]} bond interface(s): ${!BOND_NS[*]}"

# ---------------------------------------------------------------------------
# Part A — Active-backup checks
# ---------------------------------------------------------------------------
section "Part A — Active-backup bond"

AB_FOUND=false
for bond in "${!BOND_NS[@]}"; do
    ns="${BOND_NS[$bond]}"
    mode=$(bond_mode "$ns" "$bond" 2>/dev/null)
    if echo "$mode" | grep -qi 'active-backup'; then
        AB_FOUND=true
        pass "Bond $bond in $ns: mode = '$mode'"

        slave=$(bond_active_slave "$ns" "$bond")
        if [ -n "$slave" ]; then
            pass "Bond $bond: active slave = $slave"
        else
            fail "Bond $bond: no active slave reported in /proc/net/bonding/$bond"
        fi
    fi
done

$AB_FOUND || info "No active-backup bond found (skip Part A or Part A not yet built)"

# ---------------------------------------------------------------------------
# Part B — 802.3ad LACP checks
# ---------------------------------------------------------------------------
section "Part B — 802.3ad LACP bond"

LACP_FOUND=false
for bond in "${!BOND_NS[@]}"; do
    ns="${BOND_NS[$bond]}"
    mode=$(bond_mode "$ns" "$bond" 2>/dev/null)
    if echo "$mode" | grep -qi '802.3ad\|LACP'; then
        LACP_FOUND=true
        pass "Bond $bond in $ns: mode = '$mode'"

        # Check partner MAC is present and non-zero
        if bond_partner_present "$ns" "$bond"; then
            partner_mac=$(ip netns exec "$ns" cat /proc/net/bonding/"$bond" 2>/dev/null | \
                          grep -i 'partner.*mac' | head -1 | awk '{print $NF}')
            pass "Bond $bond: LACP partner MAC = $partner_mac (negotiated)"
        else
            fail "Bond $bond: LACP partner MAC is zero or missing — LACP not negotiating"
            info "Verify that both ends of the veth pair are bonded (bond0 ↔ bond1 required)"
        fi

        # At least one slave should be aggregating
        agg=$(ip netns exec "$ns" cat /proc/net/bonding/"$bond" 2>/dev/null | \
              grep -c 'Aggregator ID' || true)
        if [ "${agg:-0}" -gt 0 ]; then
            pass "Bond $bond: LACP aggregator entries found ($agg)"
        else
            info "No LACP aggregator lines found — /proc/net/bonding/$bond may show differently"
        fi
    fi
done

$LACP_FOUND || info "No 802.3ad bond found — build Part B first"

# ---------------------------------------------------------------------------
# Connectivity via bond
# ---------------------------------------------------------------------------
section "Connectivity through bond"

for ns in $(ns_list); do
    # Find a namespace that is NOT the bond owner but has a default route
    if ip -n "$ns" route show default 2>/dev/null | grep -q via; then
        gw=$(ip -j -n "$ns" route show default 2>/dev/null | jq -r '.[0].gateway' 2>/dev/null)
        if [ -n "$gw" ] && [ "$gw" != "null" ]; then
            if ping_ok "$ns" "$gw" 3; then
                pass "$ns can reach gateway $gw via bond"
            else
                fail "$ns cannot reach gateway $gw"
            fi
        fi
    fi
done

finish
