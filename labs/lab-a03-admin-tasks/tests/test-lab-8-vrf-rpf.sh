#!/usr/bin/env bash
# test-lab-8-vrf-rpf.sh — verify Lab A03-8 (VRF isolation + rp_filter).
#
# Auto-discovers: the namespace with VRF-type links.
# Checks: VRF interfaces with table numbers, in-VRF reachability,
# cross-VRF isolation, rp_filter sysctl value.
#
# Run:  ./tests/test.sh 8

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

require_cmds ip jq ping

# ---------------------------------------------------------------------------
# Auto-discover VRF namespace
# ---------------------------------------------------------------------------
section "Topology discovery"

VRF_NS=""
declare -A VRF_TABLE=()  # vrf_name → table_id

for ns in $(ns_list); do
    vrfs=$(ip -j -n "$ns" link show type vrf 2>/dev/null | \
           jq -r '.[] | .ifname' 2>/dev/null)
    count=$(echo "$vrfs" | grep -c . 2>/dev/null || echo 0)
    if [ "${count:-0}" -ge 2 ]; then
        VRF_NS="$ns"
        while IFS= read -r vrf; do
            tbl=$(ns_vrf_table "$ns" "$vrf" 2>/dev/null)
            VRF_TABLE["$vrf"]="$tbl"
        done <<< "$vrfs"
        break
    fi
done

[ -n "$VRF_NS" ] || \
    die "No namespace with ≥2 VRF interfaces found. Build the topology (lab-8-vrf-rpf.md) first."
info "VRF namespace: $VRF_NS"
info "VRFs found: $(ns_vrf_list "$VRF_NS" | tr '\n' ' ')"

# ---------------------------------------------------------------------------
# Part A — VRF structure
# ---------------------------------------------------------------------------
section "Part A — VRF interface and table IDs"

for vrf in "${!VRF_TABLE[@]}"; do
    tbl="${VRF_TABLE[$vrf]}"
    if [ -n "$tbl" ] && [ "$tbl" != "0" ]; then
        pass "VRF $vrf → routing table $tbl"
    else
        fail "VRF $vrf has no routing table or table=0"
    fi
done

# Verify interfaces are enslaved to VRFs
ENSLAVED=$(ip -j -n "$VRF_NS" link show 2>/dev/null | \
           jq '[.[] | select(.master != null and (.master | test("vrf";"i")))] | length' \
           2>/dev/null || echo 0)
if [ "${ENSLAVED:-0}" -ge 2 ]; then
    pass "$ENSLAVED interface(s) are enslaved to VRFs"
else
    fail "Expected ≥2 interfaces enslaved to VRFs; found ${ENSLAVED:-0}"
fi

# ---------------------------------------------------------------------------
# In-VRF reachability
# ---------------------------------------------------------------------------
section "In-VRF reachability"

VRF_LIST=($(ns_vrf_list "$VRF_NS"))
for vrf in "${VRF_LIST[@]}"; do
    # Find a host namespace reachable via this VRF
    VRF_ADDRS=$(ip -j -n "$VRF_NS" addr show 2>/dev/null | \
                jq -r '.[] | select(.master=="'"$vrf"'") | .addr_info[] | select(.family=="inet" and .scope=="global") | .local' \
                2>/dev/null)
    HOST_IP=""
    while IFS= read -r a; do
        # Derive host address (replace last octet with .1)
        prefix=$(echo "$a" | cut -d. -f1-3)
        HOST_IP="${prefix}.1"
        break
    done <<< "$VRF_ADDRS"

    if [ -n "$HOST_IP" ]; then
        if ip netns exec "$VRF_NS" ip vrf exec "$vrf" ping -c 3 -W 2 "$HOST_IP" >/dev/null 2>&1; then
            pass "In-VRF $vrf: can reach $HOST_IP"
        else
            fail "In-VRF $vrf: cannot reach $HOST_IP"
        fi
    fi
done

# ---------------------------------------------------------------------------
# Cross-VRF isolation
# ---------------------------------------------------------------------------
section "Cross-VRF isolation"

if [ "${#VRF_LIST[@]}" -ge 2 ]; then
    VRF_A="${VRF_LIST[0]}"
    VRF_B="${VRF_LIST[1]}"

    # Get a host in VRF B
    B_ADDRS=$(ip -j -n "$VRF_NS" addr show 2>/dev/null | \
              jq -r '.[] | select(.master=="'"$VRF_B"'") | .addr_info[] | select(.family=="inet" and .scope=="global") | .local' \
              2>/dev/null)
    B_PREFIX=$(echo "$B_ADDRS" | head -1 | cut -d. -f1-3)

    if [ -n "$B_PREFIX" ]; then
        B_HOST="${B_PREFIX}.1"
        if ip netns exec "$VRF_NS" ip vrf exec "$VRF_A" ping -c 2 -W 1 "$B_HOST" >/dev/null 2>&1; then
            fail "Cross-VRF: $VRF_A can reach $VRF_B host $B_HOST — isolation BROKEN"
        else
            pass "Cross-VRF: $VRF_A cannot reach $VRF_B host $B_HOST — isolated"
        fi
    else
        info "Could not determine VRF_B host IP for isolation check"
    fi
fi

# ---------------------------------------------------------------------------
# Part B — rp_filter
# ---------------------------------------------------------------------------
section "Part B — rp_filter sysctl"

RPF_ALL=$(ns_sysctl "$VRF_NS" "net.ipv4.conf.all.rp_filter" 2>/dev/null || echo "")
if [ -n "$RPF_ALL" ] && [ "$RPF_ALL" -ge 1 ]; then
    pass "net.ipv4.conf.all.rp_filter = $RPF_ALL (strict or loose mode enabled)"
else
    info "net.ipv4.conf.all.rp_filter = ${RPF_ALL:-0} (Part B may not be built yet)"
fi

# Check for any per-interface strict rp_filter
STRICT_IFACE=""
for iface in $(ip -j -n "$VRF_NS" link show 2>/dev/null | jq -r '.[].ifname' 2>/dev/null); do
    val=$(ns_sysctl "$VRF_NS" "net.ipv4.conf.$iface.rp_filter" 2>/dev/null || echo "0")
    if [ "${val:-0}" -ge 1 ]; then
        STRICT_IFACE="$iface"
        pass "net.ipv4.conf.$iface.rp_filter = $val (strict mode on $iface)"
        break
    fi
done

[ -z "$STRICT_IFACE" ] && [ "${RPF_ALL:-0}" -lt 1 ] && \
    info "No strict rp_filter found on any interface — build Part B first"

finish
