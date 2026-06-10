#!/usr/bin/env bash
# test-lab-2-frr-vrrpd.sh — verify Lab A04 VRRP-2 (FRR vrrpd).
#
# Checks that:
#   - FRR vrrpd reports at least one virtual-router in Master state (objective)
#   - The VIP (10.10.0.1) is assigned to the MASTER namespace (mechanism)
#   - VRRP advertisements are visible on the LAN (passive tcpdump)
#
# VERIFY-ONLY / NON-DESTRUCTIVE.
#
# Run:  ./tests/vrrp/test.sh 2

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

require_cmds ip jq vtysh tcpdump

VIP="10.10.0.1"

# ---------------------------------------------------------------------------
# Discover topology
# ---------------------------------------------------------------------------
section "Topology discovery"

FRR_NS=()
for ns in $(ns_list); do
    frr_socket_ready "$ns" && FRR_NS+=("$ns")
done

if [ "${#FRR_NS[@]}" -eq 0 ]; then
    die "No FRR instances found. Start FRR vrrpd (Lab 2 setup) first."
fi

info "FRR namespaces: ${FRR_NS[*]}"

# ---------------------------------------------------------------------------
# Part A — FRR vrrpd shows a virtual-router in Master state (objective)
# ---------------------------------------------------------------------------
section "Part A — FRR VRRP state"

MASTER_NS=""
for ns in "${FRR_NS[@]}"; do
    vrrp_out=$(ip netns exec "$ns" vtysh -N "$ns" -c 'show vrrp' 2>/dev/null)
    if echo "$vrrp_out" | grep -qi "master"; then
        MASTER_NS="$ns"
        pass "frr@$ns: vrrpd shows MASTER state"
        echo "$vrrp_out" | grep -iE '(state|master|backup|vrid|priority)' | head -6 | \
            while IFS= read -r line; do info "  $line"; done || true
    elif echo "$vrrp_out" | grep -qi "backup"; then
        info "frr@$ns: vrrpd shows BACKUP state"
    elif [ -n "$vrrp_out" ]; then
        info "frr@$ns: 'show vrrp' returned output but state unclear: $vrrp_out"
    else
        info "frr@$ns: 'show vrrp' returned nothing (vrrpd may not be enabled)"
    fi
done

[ -n "$MASTER_NS" ] || fail "No FRR namespace shows MASTER VRRP state — enable vrrpd in /etc/frr/<ns>/daemons and configure 'vrrp' in vtysh"

# ---------------------------------------------------------------------------
# Part B — VIP assigned to MASTER namespace (mechanism)
# ---------------------------------------------------------------------------
section "Part B — VIP on MASTER namespace"

if [ -n "$MASTER_NS" ]; then
    has_vip=$(ip -j -n "$MASTER_NS" addr show 2>/dev/null | \
              jq -e --arg vip "$VIP" 'any(.[].addr_info[]; .family=="inet" and .local==$vip)' \
              2>/dev/null && echo true || echo false)
    if [ "$has_vip" = "true" ]; then
        pass "MASTER ($MASTER_NS) has VIP $VIP assigned via ip addr (virtual IP is real)"
    else
        fail "MASTER ($MASTER_NS) shows MASTER state in vrrpd but VIP $VIP is not in ip addr show"
    fi
fi

# ---------------------------------------------------------------------------
# Part C — VRRP advertisements visible (mechanism)
# ---------------------------------------------------------------------------
section "Part C — VRRP advertisements on LAN"

# Find LAN bridge namespace
LAN_NS=""
for ns in $(ns_list); do
    has_bridge=$(ip -j -n "$ns" link show type bridge 2>/dev/null | jq 'length > 0' 2>/dev/null || echo false)
    if [ "$has_bridge" = "true" ]; then
        LAN_NS="$ns"
        break
    fi
done

if [ -n "$LAN_NS" ]; then
    br=$(ip -j -n "$LAN_NS" link show type bridge 2>/dev/null | jq -r '.[0].ifname // empty' 2>/dev/null)
    if [ -n "$br" ]; then
        cap="$_WORKDIR/vrrp2-cap.txt"
        info "Capturing VRRP on $LAN_NS/$br for 4 seconds..."
        tcpdump_start "$LAN_NS" "$br" "$cap" 4 "proto vrrp"
        sleep 4
        cnt=$(tcpdump_match_count "$cap" "VRRPv[23]|vrrp")
        if [ "${cnt:-0}" -gt 0 ]; then
            pass "VRRP advertisements from FRR vrrpd visible ($cnt packet(s))"
        else
            fail "No VRRP advertisements — check that vrrpd is enabled and the VR is configured on the LAN interface"
        fi
    else
        info "No bridge in LAN namespace — skipping capture"
    fi
else
    info "No LAN bridge namespace found — skipping VRRP capture"
fi

finish
