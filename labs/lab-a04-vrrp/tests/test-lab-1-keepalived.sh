#!/usr/bin/env bash
# test-lab-1-keepalived.sh — verify Lab A04 VRRP-1 (keepalived).
#
# Checks that:
#   - The virtual IP (10.10.0.1) is assigned to exactly one namespace (MASTER)
#   - It is absent from the BACKUP namespace
#   - VRRP advertisement packets are being sent (passive tcpdump)
#   - The VIP is pingable from the LAN namespace (end-to-end objective)
#
# VERIFY-ONLY / NON-DESTRUCTIVE.  Does not kill keepalived or change priorities.
# Auto-discovers which namespace is MASTER by checking for VIP assignment.
#
# Run:  ./tests/vrrp/test.sh 1

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

require_cmds ip jq tcpdump ping

VIP="10.10.0.1"
VRRP_GROUP="224.0.0.18"

# ---------------------------------------------------------------------------
# Discover topology
# ---------------------------------------------------------------------------
section "Topology discovery"

MASTER=""
BACKUP_LIST=()
LAN_NS=""

for ns in $(ns_list); do
    # Look for any iface that has the VIP
    has_vip=$(ip -j -n "$ns" addr show 2>/dev/null | \
              jq -e --arg vip "$VIP" '
                  any(.[].addr_info[]; .family=="inet" and .local==$vip)
              ' 2>/dev/null && echo true || echo false)
    if [ "$has_vip" = "true" ]; then
        MASTER="$ns"
        info "MASTER namespace: $ns (has VIP $VIP)"
    fi
    # LAN namespace has a bridge and no VIP
    has_bridge=$(ip -j -n "$ns" link show type bridge 2>/dev/null | jq 'length > 0' 2>/dev/null || echo false)
    if [ "$has_bridge" = "true" ] && [ "$has_vip" = "false" ]; then
        LAN_NS="$ns"
        info "LAN bridge namespace: $ns"
    fi
done

# Namespaces without the VIP and without being LAN are BACKUP candidates
for ns in $(ns_list); do
    [ "$ns" = "$MASTER" ] && continue
    [ "$ns" = "$LAN_NS" ] && continue
    # Check if keepalived is running in this ns (indicates BACKUP VRRP router)
    if ip netns exec "$ns" pgrep keepalived >/dev/null 2>&1; then
        BACKUP_LIST+=("$ns")
        info "BACKUP namespace: $ns"
    fi
done

if [ -z "$MASTER" ]; then
    die "No namespace has VIP $VIP assigned. Start keepalived (Lab 1) and wait a few seconds."
fi

# ---------------------------------------------------------------------------
# Part A — VIP is on MASTER (objective)
# ---------------------------------------------------------------------------
section "Part A — VIP assigned to MASTER"

if vip_on_iface "$MASTER" "" "$VIP" || \
   ip -j -n "$MASTER" addr show 2>/dev/null | \
       jq -e --arg vip "$VIP" 'any(.[].addr_info[]; .family=="inet" and .local==$vip)' >/dev/null 2>&1; then
    pass "MASTER ($MASTER) has VIP $VIP assigned"
else
    fail "MASTER ($MASTER) does not have VIP $VIP — keepalived may not be running"
fi

# ---------------------------------------------------------------------------
# Part B — VIP absent from BACKUP (mechanism)
# ---------------------------------------------------------------------------
section "Part B — VIP absent from BACKUP"

for bns in "${BACKUP_LIST[@]}"; do
    has_vip=$(ip -j -n "$bns" addr show 2>/dev/null | \
              jq --arg vip "$VIP" 'any(.[].addr_info[]; .family=="inet" and .local==$vip)' \
              2>/dev/null || echo false)
    if [ "$has_vip" = "false" ]; then
        pass "BACKUP ($bns) does NOT have VIP $VIP (correct — only MASTER should)"
    else
        fail "BACKUP ($bns) unexpectedly has VIP $VIP — both routers may be MASTER"
    fi
done

# ---------------------------------------------------------------------------
# Part C — VRRP advertisements visible on LAN (mechanism)
# ---------------------------------------------------------------------------
section "Part C — VRRP advertisement packets present"

if [ -n "$LAN_NS" ]; then
    # Find the bridge interface
    br=$(ip -j -n "$LAN_NS" link show type bridge 2>/dev/null | jq -r '.[0].ifname // empty' 2>/dev/null)
    if [ -n "$br" ]; then
        cap="$_WORKDIR/vrrp-cap.txt"
        info "Capturing VRRP on $LAN_NS/$br for 4 seconds..."
        tcpdump_start "$LAN_NS" "$br" "$cap" 4 "proto vrrp"
        sleep 4
        vrrp_count=$(tcpdump_match_count "$cap" "VRRPv[23]|vrrp")
        if [ "${vrrp_count:-0}" -gt 0 ]; then
            pass "VRRP advertisements visible on LAN bridge ($vrrp_count packet(s) captured)"
        else
            fail "No VRRP advertisements seen on LAN bridge — keepalived not sending?"
        fi
    else
        info "No bridge found in LAN namespace — skipping VRRP capture"
    fi
else
    info "No LAN namespace identified — skipping VRRP capture (run the 3-namespace topology)"
fi

# ---------------------------------------------------------------------------
# Part D — VIP pingable from LAN (end-to-end objective)
# ---------------------------------------------------------------------------
section "Part D — VIP pingable from LAN namespace"

if [ -n "$LAN_NS" ]; then
    if ping_ok "$LAN_NS" "$VIP" 3; then
        pass "VIP $VIP is pingable from LAN namespace ($LAN_NS)"
    else
        fail "VIP $VIP is NOT pingable from LAN namespace — routing or ARP issue?"
    fi
else
    info "No LAN namespace — skipping ping test"
fi

finish
