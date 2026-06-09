#!/usr/bin/env bash
# test-lab-10-mtu-pmtu.sh — verify Lab A03-10 (MTU + PMTU discovery).
#
# Auto-discovers: the namespace pair with a constrained-MTU veth (MTU < 1500).
# Checks: per-interface MTU, ping-M-do large payload fails / small passes,
# route cache shows reduced MTU after failed probe.
#
# Run:  ./tests/test.sh 10

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

require_cmds ip jq ping

# ---------------------------------------------------------------------------
# Auto-discover
# ---------------------------------------------------------------------------
section "Topology discovery"

# Find the namespace/interface pair with MTU < 1500 and ≠ 65536 (loopback)
CONSTRAINED_NS=""
CONSTRAINED_IFACE=""
CONSTRAINED_MTU=""
FULL_NS=""

# Find the constrained endpoint: a namespace whose veths are ALL constrained
# (no 1500-MTU veth alongside a constrained one — rules out the transit router).
for ns in $(ns_list); do
    veth_data=$(ip -d -j -n "$ns" link show 2>/dev/null | \
                jq -r '.[] | select(.linkinfo.info_kind? == "veth") | "\(.ifname) \(.mtu)"' \
                2>/dev/null)
    [ -z "$veth_data" ] && continue
    has_full=false
    has_constrained=false
    ci="" cm=""
    while IFS=' ' read -r iface mtu; do
        [ -z "$mtu" ] && continue
        if [ "$mtu" -ge 1500 ]; then
            has_full=true
        elif [ "$mtu" -gt 576 ]; then
            has_constrained=true
            ci="$iface"; cm="$mtu"
        fi
    done <<< "$veth_data"
    # Endpoint: has constrained veths but NO full-MTU veths (transit router has both)
    if $has_constrained && ! $has_full; then
        CONSTRAINED_NS="$ns"; CONSTRAINED_IFACE="$ci"; CONSTRAINED_MTU="$cm"
        break
    fi
done

# Fallback: any namespace with a constrained veth (picks transit router if no pure endpoint)
if [ -z "$CONSTRAINED_NS" ]; then
    for ns in $(ns_list); do
        ifaces=$(ip -d -j -n "$ns" link show 2>/dev/null | \
                 jq -r '.[] | select(.linkinfo.info_kind? == "veth") | "\(.ifname) \(.mtu)"' \
                 2>/dev/null)
        while IFS=' ' read -r iface mtu; do
            if [ -n "$mtu" ] && [ "$mtu" -lt 1500 ] && [ "$mtu" -gt 576 ]; then
                CONSTRAINED_NS="$ns"; CONSTRAINED_IFACE="$iface"; CONSTRAINED_MTU="$mtu"
                break 2
            fi
        done <<< "$ifaces"
    done
fi

[ -n "$CONSTRAINED_NS" ] || \
    die "No interface with MTU < 1500 found. Build the topology (lab-10-mtu-pmtu.md) first."
info "Constrained: $CONSTRAINED_NS/$CONSTRAINED_IFACE MTU=$CONSTRAINED_MTU"

# Find the full-MTU source host: a namespace with ONLY 1500-MTU veths (never the constrained side)
for ns in $(ns_list); do
    [ "$ns" = "$CONSTRAINED_NS" ] && continue
    veth_data=$(ip -d -j -n "$ns" link show 2>/dev/null | \
                jq -r '.[] | select(.linkinfo.info_kind? == "veth") | "\(.ifname) \(.mtu)"' \
                2>/dev/null)
    [ -z "$veth_data" ] && continue
    all_full=true
    while IFS=' ' read -r iface mtu; do
        [ -z "$mtu" ] && continue
        [ "$mtu" -lt 1500 ] && { all_full=false; break; }
    done <<< "$veth_data"
    if $all_full; then FULL_NS="$ns"; break; fi
done
[ -n "$FULL_NS" ] || FULL_NS=$(ns_list | grep -v "^${CONSTRAINED_NS}$" | head -1)
info "Full-MTU source namespace: $FULL_NS"

# ---------------------------------------------------------------------------
# MTU configuration
# ---------------------------------------------------------------------------
section "Interface MTU verification"

FULL_MTU=$(ns_iface_mtu "$CONSTRAINED_NS" "$CONSTRAINED_IFACE")
if [ -n "$FULL_MTU" ] && [ "$FULL_MTU" -eq "$CONSTRAINED_MTU" ]; then
    pass "Interface $CONSTRAINED_IFACE in $CONSTRAINED_NS has MTU $CONSTRAINED_MTU"
else
    fail "MTU mismatch: got $FULL_MTU, expected $CONSTRAINED_MTU"
fi

# Find h1 (the sender) — non-constrained, non-forwarding namespace
H1_NS=""
for ns in $(ns_list); do
    [ "$ns" = "$CONSTRAINED_NS" ] && continue
    fwd=$(ns_forwarding "$ns")
    if [ "$fwd" != "1" ]; then
        H1_NS="$ns"
        break
    fi
done

if [ -n "$H1_NS" ]; then
    H1_IFACE=$(ip -j -n "$H1_NS" link show 2>/dev/null | \
               jq -r '.[] | select(.ifname!="lo") | .ifname' 2>/dev/null | head -1)
    H1_MTU=$(ns_iface_mtu "$H1_NS" "$H1_IFACE")
    if [ "${H1_MTU:-0}" -ge 1500 ]; then
        pass "Source interface $H1_IFACE in $H1_NS has full MTU $H1_MTU"
    fi
fi

# ---------------------------------------------------------------------------
# ping -M do probes
# ---------------------------------------------------------------------------
section "PMTU probes (ping -M do)"

# Find destination: the constrained-side host
DST_NS="$CONSTRAINED_NS"
DST_ADDR=$(ip -j -n "$DST_NS" addr show 2>/dev/null | \
           jq -r '.[] | .addr_info[] | select(.family=="inet" and .scope=="global") | .local' \
           2>/dev/null | head -1)

SRC_NS="$FULL_NS"

if [ -z "$SRC_NS" ] || [ -z "$DST_ADDR" ]; then
    info "Cannot determine source/destination — skipping ping-M-do tests"
    finish
fi

info "Probing: $SRC_NS → $DST_ADDR"

# Small probe: ICMP + 20 bytes IP header + 8 bytes ICMP = 28; payload = MTU-28
SMALL_PAYLOAD=$(( CONSTRAINED_MTU - 28 ))
if ip netns exec "$SRC_NS" ping -M do -c 2 -W 2 -s "$SMALL_PAYLOAD" "$DST_ADDR" >/dev/null 2>&1; then
    pass "Small probe (${SMALL_PAYLOAD}B payload, ${CONSTRAINED_MTU}B total) succeeds"
else
    fail "Small probe (${SMALL_PAYLOAD}B payload) failed — topology or routing issue"
fi

# Large probe: 1 byte over the constrained MTU should fail
LARGE_PAYLOAD=$(( CONSTRAINED_MTU - 28 + 100 ))
if ip netns exec "$SRC_NS" ping -M do -c 1 -W 2 -s "$LARGE_PAYLOAD" "$DST_ADDR" >/dev/null 2>&1; then
    fail "Large probe (${LARGE_PAYLOAD}B payload) succeeded — expected PMTU failure"
else
    pass "Large probe (${LARGE_PAYLOAD}B payload) rejected — ICMP Frag Needed working"
fi

# ---------------------------------------------------------------------------
# PMTU cache
# ---------------------------------------------------------------------------
section "PMTU cache"

# After the failing probe the kernel caches the PMTU
sleep 1  # give kernel time to process the ICMP response

CACHED_MTU=$(ns_route_pmtu "$SRC_NS" "$DST_ADDR" 2>/dev/null)
if [ -n "$CACHED_MTU" ] && [ "$CACHED_MTU" -le "$CONSTRAINED_MTU" ]; then
    pass "Route cache for $DST_ADDR shows mtu $CACHED_MTU (≤ $CONSTRAINED_MTU)"
else
    # Also check via ip route get
    ROUTE_GET=$(ip -n "$SRC_NS" route get "$DST_ADDR" 2>/dev/null)
    if echo "$ROUTE_GET" | grep -q 'mtu'; then
        MTU_VAL=$(echo "$ROUTE_GET" | grep -oE 'mtu [0-9]+' | awk '{print $2}')
        if [ "${MTU_VAL:-1500}" -le "$CONSTRAINED_MTU" ]; then
            pass "Route cache mtu $MTU_VAL (≤ $CONSTRAINED_MTU) from ip route get"
        else
            fail "Route cache mtu $MTU_VAL > constrained MTU $CONSTRAINED_MTU"
        fi
    else
        info "No PMTU cache entry yet — trigger with: ping -M do -s $LARGE_PAYLOAD $DST_ADDR"
    fi
fi

finish
