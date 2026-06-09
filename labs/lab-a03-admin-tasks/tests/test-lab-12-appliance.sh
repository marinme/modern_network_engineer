#!/usr/bin/env bash
# test-lab-12-appliance.sh — verify Lab A03-12 (full wan–r–lan appliance).
#
# Auto-discovers: the namespace with masquerade + dnat + forward-drop policy.
# Checks: forwarding, NAT rules, ACL policy, DHCP lease, conntrack flows,
# iperf3 result throughput > 0.
#
# Run:  ./tests/test.sh 12

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

require_cmds ip nft jq conntrack ping

# ---------------------------------------------------------------------------
# Auto-discover appliance namespace
# ---------------------------------------------------------------------------
section "Topology discovery"

APP_NS=""
for ns in $(ns_list); do
    if ns_forwarding "$ns" | grep -q 1 && ns_nft_has_rule "$ns" 'masquerade'; then
        APP_NS="$ns"
        break
    fi
done

[ -n "$APP_NS" ] || \
    die "No appliance namespace found (need ip_forward=1 + masquerade rule). Build the topology first."
info "Appliance namespace: $APP_NS"

WAN_NS="" LAN_NS="" SRV_NS=""
for ns in $(ns_list); do
    [ "$ns" = "$APP_NS" ] && continue
    addrs=$(ip -j -n "$ns" addr show 2>/dev/null | \
            jq -r '.[] | .addr_info[] | select(.family=="inet" and .scope=="global") | .local' \
            2>/dev/null)
    while IFS= read -r a; do
        case "$a" in
            172.*) WAN_NS="$ns";;
            10.0.0.10) SRV_NS="$ns";;
            10.0.0.[1-9][0-9][0-9]) LAN_NS="$ns";;  # DHCP range 100-200
        esac
    done <<< "$addrs"
done

info "WAN: ${WAN_NS:-unknown}  LAN: ${LAN_NS:-unknown}  SRV: ${SRV_NS:-unknown}"

# ---------------------------------------------------------------------------
# IP forwarding
# ---------------------------------------------------------------------------
section "IP forwarding"

FWD=$(ns_forwarding "$APP_NS")
if [ "$FWD" = "1" ]; then
    pass "net.ipv4.ip_forward=1 in $APP_NS"
else
    fail "net.ipv4.ip_forward is $FWD in $APP_NS"
fi

# ---------------------------------------------------------------------------
# NFtables ruleset
# ---------------------------------------------------------------------------
section "NFTables: complete appliance ruleset"

if ns_nft_has_rule "$APP_NS" 'masquerade'; then
    pass "Masquerade (PAT) rule present"
else
    fail "Masquerade rule missing"
fi

if ns_nft_has_rule "$APP_NS" 'dnat'; then
    DNAT_RULE=$(ip netns exec "$APP_NS" nft list ruleset 2>/dev/null | grep dnat | head -1 | xargs)
    pass "DNAT rule present: $DNAT_RULE"
else
    fail "DNAT rule missing"
fi

POLICY=$(ns_nft_chain_policy "$APP_NS" filter ip forward 2>/dev/null)
if echo "$POLICY" | grep -qi drop; then
    pass "Forward chain has policy drop (ACL default-deny)"
else
    # Alternative JSON check
    POL=$(ip netns exec "$APP_NS" nft -j list ruleset 2>/dev/null | \
          jq -r '.nftables[] | .chain? | select(.name=="forward") | .policy' 2>/dev/null)
    if [ "${POL,,}" = "drop" ]; then
        pass "Forward chain policy drop (via JSON)"
    else
        fail "Forward chain policy is not drop (got: ${POLICY:-${POL:-empty}})"
    fi
fi

if ns_nft_has_rule "$APP_NS" 'ct state established'; then
    pass "ct state established,related rule present in forward chain"
else
    fail "ct state established,related rule missing"
fi

if ip netns exec "$APP_NS" nft list ruleset 2>/dev/null | grep -q 'prerouting'; then
    pass "prerouting chain present (correct hook for DNAT)"
fi

if ip netns exec "$APP_NS" nft list ruleset 2>/dev/null | grep -q 'postrouting'; then
    pass "postrouting chain present (correct hook for masquerade)"
fi

# ---------------------------------------------------------------------------
# DHCP lease
# ---------------------------------------------------------------------------
section "DHCP lease"

LEASE_FILE="/tmp/leases-r.txt"
if [ -f "$LEASE_FILE" ]; then
    LEASE_COUNT=$(wc -l < "$LEASE_FILE" 2>/dev/null || echo 0)
    if [ "${LEASE_COUNT:-0}" -gt 0 ]; then
        LEASE_IP=$(awk '{print $3}' "$LEASE_FILE" | head -1)
        pass "DHCP lease file has $LEASE_COUNT entry(entries) — last leased IP: $LEASE_IP"

        # Confirm lease is in pool (10.0.0.100-200)
        FOURTH=$(echo "$LEASE_IP" | cut -d. -f4)
        PREFIX=$(echo "$LEASE_IP" | cut -d. -f1-3)
        if [ "$PREFIX" = "10.0.0" ] && [ "${FOURTH:-0}" -ge 100 ] && [ "${FOURTH:-0}" -le 200 ]; then
            pass "Leased IP $LEASE_IP is within pool 10.0.0.100-200"
        else
            info "Leased IP $LEASE_IP is outside expected pool 10.0.0.100-200"
        fi
    else
        fail "DHCP lease file $LEASE_FILE is empty — run dhclient in lan namespace"
    fi
else
    info "DHCP lease file $LEASE_FILE not found — run: ip netns exec lan dhclient -v veth-lan-r"
fi

# ---------------------------------------------------------------------------
# Connectivity probes
# ---------------------------------------------------------------------------
section "Connectivity"

if [ -n "$LAN_NS" ] && [ -n "$WAN_NS" ]; then
    WAN_ADDR=$(ip -j -n "$WAN_NS" addr show 2>/dev/null | \
               jq -r '.[] | .addr_info[] | select(.family=="inet" and .scope=="global") | .local' \
               2>/dev/null | head -1)
    if ping_ok "$LAN_NS" "$WAN_ADDR" 3; then
        pass "LAN → WAN ping ($WAN_ADDR) works (masquerade path)"
    else
        fail "LAN cannot reach WAN ($WAN_ADDR)"
    fi
fi

# ACL: uninitiated inbound should be dropped
if [ -n "$WAN_NS" ] && [ -n "$LAN_NS" ]; then
    LAN_ADDR=$(ip -j -n "$LAN_NS" addr show 2>/dev/null | \
               jq -r '.[] | .addr_info[] | select(.family=="inet" and .scope=="global") | .local' \
               2>/dev/null | head -1)
    if [ -n "$LAN_ADDR" ]; then
        LOSS=$(ping_loss "$WAN_NS" "$LAN_ADDR" 2)
        if [ "${LOSS:-100}" -eq 100 ]; then
            pass "WAN cannot reach LAN host unprompted (forward policy drop working)"
        else
            fail "WAN can reach LAN host without prior LAN-initiation (ACL not working)"
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Conntrack
# ---------------------------------------------------------------------------
section "Conntrack NAT flows"

# Drive a flow to populate conntrack
if [ -n "$LAN_NS" ] && [ -n "$WAN_NS" ]; then
    WAN_ADDR=$(ip -j -n "$WAN_NS" addr show 2>/dev/null | \
               jq -r '.[] | .addr_info[] | select(.family=="inet" and .scope=="global") | .local' \
               2>/dev/null | head -1)
    ping_ok "$LAN_NS" "$WAN_ADDR" 3 >/dev/null 2>&1 || true
fi

CT=$(ns_conntrack_count "$APP_NS")
if [ "${CT:-0}" -gt 0 ]; then
    pass "Conntrack table has $CT entries"
else
    fail "Conntrack table is empty — generate traffic first"
fi

if ns_conntrack_has "$APP_NS" 'ESTABLISHED\|SNAT\|MASQUERADE\|icmp\|tcp'; then
    pass "Conntrack shows live flows (NAT active)"
fi

# ---------------------------------------------------------------------------
# Interface counters
# ---------------------------------------------------------------------------
section "Interface byte counters"

for ns in $(ns_list); do
    [ "$ns" = "$APP_NS" ] && continue
    # Only check namespaces with forwarding on (skip hosts)
    break
done

for iface in $(ip -j -n "$APP_NS" link show 2>/dev/null | jq -r '.[] | select(.ifname!="lo") | .ifname' 2>/dev/null); do
    TX=$(link_tx_bytes "$APP_NS" "$iface")
    RX=$(link_rx_bytes "$APP_NS" "$iface")
    if [ "${TX:-0}" -gt 0 ] || [ "${RX:-0}" -gt 0 ]; then
        pass "Interface $iface in $APP_NS: TX=$TX RX=$RX bytes (non-zero counters)"
    fi
done

# ---------------------------------------------------------------------------
# iperf3 result
# ---------------------------------------------------------------------------
section "iperf3 throughput"

IPERF_FILE="/tmp/iperf3-result.json"
if [ -f "$IPERF_FILE" ]; then
    BPS=$(jq '.end.sum_received.bits_per_second // 0' "$IPERF_FILE" 2>/dev/null || echo 0)
    MBPS=$(echo "$BPS / 1000000" | awk '{printf "%.1f", $0}' 2>/dev/null || echo "0")
    if [ "$(echo "$BPS > 0" | awk '{print ($1+0 > 0) ? 1 : 0}')" = "1" ]; then
        pass "iperf3 throughput: ${MBPS} Mbps (non-zero)"
    else
        fail "iperf3 result shows 0 bps — run the health sweep first"
    fi
else
    info "No iperf3 result file at $IPERF_FILE — run the health sweep section first"
fi

finish
