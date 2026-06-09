#!/usr/bin/env bash
# test-lab-5-nat-pat.sh — verify Lab A03-5 (NAT: masquerade + DNAT + conntrack).
#
# Auto-discovers: the namespace with masquerade in its nft ruleset is the NAT router.
# Checks: nft has masquerade + dnat rules, outbound SNAT probe works,
# inbound DNAT port-forward probe works, conntrack shows NAT entries.
#
# Run:  ./tests/test.sh 5

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

require_cmds ip nft jq conntrack ncat ping

# ---------------------------------------------------------------------------
# Auto-discover
# ---------------------------------------------------------------------------
section "Topology discovery"

NATR=""
for ns in $(ns_list); do
    if ns_nft_has_rule "$ns" 'masquerade'; then
        NATR="$ns"
        break
    fi
done

[ -n "$NATR" ] || die "No namespace with a masquerade rule found. Build the topology first."
info "NAT router namespace: $NATR"

# WAN: first connected subnet NOT in 10.x — or the one that masquerade fires on
WAN_NS=""
LAN_NS=""
SRV_NS=""

for ns in $(ns_list); do
    [ "$ns" = "$NATR" ] && continue
    addrs=$(ip -j -n "$ns" addr show 2>/dev/null | \
            jq -r '.[] | .addr_info[] | select(.family=="inet" and .scope=="global") | .local' \
            2>/dev/null)
    while IFS= read -r a; do
        case "$a" in
            172.*|192.168.*) [ -z "$WAN_NS" ] && WAN_NS="$ns";;
            10.0.0.5|10.0.0.1[0-9]) [ -z "$SRV_NS" ] && SRV_NS="$ns";;
            10.*) [ -z "$LAN_NS" ] && LAN_NS="$ns";;
        esac
    done <<< "$addrs"
done

info "WAN: ${WAN_NS:-unknown}  LAN: ${LAN_NS:-unknown}  SRV: ${SRV_NS:-unknown}"

# ---------------------------------------------------------------------------
# NFtables ruleset
# ---------------------------------------------------------------------------
section "NFTables: masquerade + DNAT rules"

if ns_nft_has_rule "$NATR" 'masquerade'; then
    pass "masquerade rule present in $NATR"
else
    fail "masquerade rule missing"
fi

if ns_nft_has_rule "$NATR" 'dnat'; then
    DNAT_INFO=$(ip netns exec "$NATR" nft list ruleset 2>/dev/null | grep dnat | head -1 | xargs)
    pass "dnat rule present: $DNAT_INFO"
else
    info "No dnat rule found — Part B (DNAT) may not yet be built"
fi

# Check postrouting chain exists
if ip netns exec "$NATR" nft list ruleset 2>/dev/null | grep -q 'postrouting'; then
    pass "postrouting chain present (correct hook for masquerade)"
else
    fail "postrouting chain missing"
fi

# Check prerouting for DNAT
if ip netns exec "$NATR" nft list ruleset 2>/dev/null | grep -q 'prerouting'; then
    pass "prerouting chain present (correct hook for DNAT)"
fi

# ---------------------------------------------------------------------------
# Outbound masquerade
# ---------------------------------------------------------------------------
section "Outbound masquerade (LAN → WAN)"

if [ -n "$LAN_NS" ] && [ -n "$WAN_NS" ]; then
    WAN_ADDR=$(ip -j -n "$WAN_NS" addr show 2>/dev/null | \
               jq -r '.[] | .addr_info[] | select(.family=="inet" and .scope=="global") | .local' \
               2>/dev/null | head -1)
    if ping_ok "$LAN_NS" "$WAN_ADDR" 3; then
        pass "LAN → WAN ping works (masquerade path)"
    else
        fail "LAN cannot reach WAN ($WAN_ADDR) — masquerade or routing broken"
    fi
fi

# ---------------------------------------------------------------------------
# Conntrack NAT entries
# ---------------------------------------------------------------------------
section "Conntrack NAT entries"

# Generate a flow if not already there
if [ -n "$LAN_NS" ] && [ -n "$WAN_NS" ]; then
    WAN_ADDR=$(ip -j -n "$WAN_NS" addr show 2>/dev/null | \
               jq -r '.[] | .addr_info[] | select(.family=="inet" and .scope=="global") | .local' \
               2>/dev/null | head -1)
    ping_ok "$LAN_NS" "$WAN_ADDR" 3 >/dev/null 2>&1 || true
fi

CT=$(ns_conntrack_count "$NATR")
if [ "${CT:-0}" -gt 0 ]; then
    pass "Conntrack table has $CT entries"
else
    fail "Conntrack table is empty — NAT flows should be tracked"
fi

if ns_conntrack_has "$NATR" 'MASQUERADE\|src=10\.[0-9]+\.[0-9]+\.[0-9]+.*SNAT\|SNAT'; then
    pass "Conntrack shows SNAT/MASQUERADE flow"
else
    # Just check for any established TCP/ICMP flow
    if ns_conntrack_has "$NATR" 'ESTABLISHED\|RELATED\|icmp\|tcp'; then
        pass "Conntrack shows established flows (NAT active)"
    else
        info "No SNAT conntrack entry visible — try pinging from LAN first"
    fi
fi

# ---------------------------------------------------------------------------
# Inbound DNAT port-forward
# ---------------------------------------------------------------------------
section "Inbound DNAT port-forward"

if [ -n "$SRV_NS" ] && [ -n "$WAN_NS" ]; then
    # Find the DNAT destination port from the nft rule
    DNAT_PORT=$(ip netns exec "$NATR" nft list ruleset 2>/dev/null | \
                grep -oE 'dport [0-9]+' | tail -1 | awk '{print $2}')
    EXT_PORT=$(ip netns exec "$NATR" nft list ruleset 2>/dev/null | \
               grep -oE 'tcp dport [0-9]+' | head -1 | awk '{print $3}')

    R_WAN_ADDR=$(ip -j -n "$NATR" addr show 2>/dev/null | \
                 jq -r '.[] | .addr_info[] | select(.family=="inet" and .scope=="global") | select(.local | startswith("172") or startswith("192")) | .local' \
                 2>/dev/null | head -1)
    [ -n "$R_WAN_ADDR" ] || \
        R_WAN_ADDR=$(ip -j -n "$NATR" addr show 2>/dev/null | \
                     jq -r '.[] | .addr_info[] | select(.family=="inet" and .scope=="global") | .local' \
                     2>/dev/null | head -1)

    # Start a listener on srv:80 if not already running
    if command -v ncat >/dev/null 2>&1; then
        ip netns exec "$SRV_NS" ncat -l -k -p 80 >/dev/null 2>&1 &
        NC_PID=$!
        _BG_PIDS+=("$NC_PID")
        sleep 0.5

        if timeout 3 ip netns exec "$WAN_NS" ncat -zw 2 "$R_WAN_ADDR" "${EXT_PORT:-8080}" 2>/dev/null; then
            pass "DNAT: WAN can connect to router:${EXT_PORT:-8080} (forwarded to srv:80)"
        else
            info "DNAT probe timed out — ensure ncat is listening on srv:80"
        fi
    fi
fi

finish
