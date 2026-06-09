#!/usr/bin/env bash
# test-lab-3-vlan-trunk.sh — verify Lab A03-3 (VLAN-aware bridges + trunk).
#
# Auto-discovers: namespaces with bridges that have vlan_filtering=1.
# Checks: filtering enabled, VLANs configured, same-VLAN reach, cross-VLAN
# isolation, 802.1Q tags present in captures.
#
# Run:  ./tests/test.sh 3

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

require_cmds ip bridge jq ping tcpdump

# ---------------------------------------------------------------------------
# Auto-discover topology
# ---------------------------------------------------------------------------
section "Topology discovery"

SW_NSS=()
for ns in $(ns_list); do
    for br in $(ns_bridges "$ns" 2>/dev/null); do
        if ns_vlan_filtering "$ns" "$br"; then
            SW_NSS+=("$ns:$br")
        fi
    done
done

[ "${#SW_NSS[@]}" -ge 1 ] || \
    die "No VLAN-filtering bridges found. Build the topology first (lab-3-vlan-trunk.md)."

info "Found ${#SW_NSS[@]} VLAN-filtering bridge(s): ${SW_NSS[*]}"

SW1_NS="${SW_NSS[0]%%:*}"
SW1_BR="${SW_NSS[0]##*:}"

# ---------------------------------------------------------------------------
# Bridge structure
# ---------------------------------------------------------------------------
section "Bridge and VLAN structure"

if ns_vlan_filtering "$SW1_NS" "$SW1_BR"; then
    pass "Bridge $SW1_BR in $SW1_NS has vlan_filtering=1"
else
    fail "Bridge $SW1_BR in $SW1_NS does NOT have vlan_filtering"
fi

# Check that at least two different VLANs are configured on the bridge
ALL_VLANS=$(bridge -j -n "$SW1_NS" vlan show 2>/dev/null | \
            jq -r '.[].vlans[]? | .vlan' 2>/dev/null | sort -un)
VLAN_COUNT=$(echo "$ALL_VLANS" | grep -c . 2>/dev/null || echo 0)

if [ "$VLAN_COUNT" -ge 2 ]; then
    pass "Bridge $SW1_BR has $VLAN_COUNT distinct VLANs configured: $(echo "$ALL_VLANS" | tr '\n' ' ')"
else
    fail "Bridge $SW1_BR has only $VLAN_COUNT VLAN(s); need at least 2 (e.g. VLAN 10 and 20)"
fi

# Check trunk port: must have >1 VLAN
TRUNK_PORT=""
while IFS= read -r port; do
    [ "$port" = "$SW1_BR" ] && continue
    VL=$(port_vlans "$SW1_NS" "$port" | wc -l)
    if [ "$VL" -ge 2 ]; then
        TRUNK_PORT="$port"
        info "Trunk port: $port (carries VLANs: $(port_vlans "$SW1_NS" "$port" | tr '\n' ' '))"
        break
    fi
done < <(ns_bridge_ports "$SW1_NS" "$SW1_BR")

if [ -n "$TRUNK_PORT" ]; then
    pass "Trunk port $TRUNK_PORT carries multiple VLANs"
else
    fail "No trunk port found (no bridge port with ≥2 VLANs); complete Part B first"
fi

# ---------------------------------------------------------------------------
# Reachability within VLANs
# ---------------------------------------------------------------------------
section "Same-VLAN reachability"

# Find hosts on VLAN 10 and VLAN 20 (by searching for 10.x.10.x and 10.x.20.x addresses)
VLAN10_HOSTS=()
VLAN20_HOSTS=()
for ns in $(ns_list); do
    addrs=$(ip -j -n "$ns" addr show 2>/dev/null | \
            jq -r '.[] | .addr_info[] | select(.family=="inet" and .scope=="global") | .local' \
            2>/dev/null)
    while IFS= read -r addr; do
        case "$addr" in
            10.*.10.*) VLAN10_HOSTS+=("$ns:$addr");;
            10.*.20.*) VLAN20_HOSTS+=("$ns:$addr");;
        esac
    done <<< "$addrs"
done

if [ "${#VLAN10_HOSTS[@]}" -ge 2 ]; then
    NS1="${VLAN10_HOSTS[0]%%:*}"; IP1="${VLAN10_HOSTS[0]##*:}"
    NS2="${VLAN10_HOSTS[1]%%:*}"; IP2="${VLAN10_HOSTS[1]##*:}"
    if ping_ok "$NS1" "$IP2" 3; then
        pass "VLAN10: $NS1 can reach $NS2 ($IP2)"
    else
        fail "VLAN10: $NS1 cannot reach $NS2 ($IP2) — same-VLAN reachability broken"
    fi
else
    info "Could not auto-discover two VLAN-10 hosts; skipping same-VLAN ping test"
fi

if [ "${#VLAN20_HOSTS[@]}" -ge 2 ]; then
    NS1="${VLAN20_HOSTS[0]%%:*}"; IP1="${VLAN20_HOSTS[0]##*:}"
    NS2="${VLAN20_HOSTS[1]%%:*}"; IP2="${VLAN20_HOSTS[1]##*:}"
    if ping_ok "$NS1" "$IP2" 3; then
        pass "VLAN20: $NS1 can reach $NS2 ($IP2)"
    else
        fail "VLAN20: $NS1 cannot reach $NS2 ($IP2) — same-VLAN reachability broken"
    fi
else
    info "Could not auto-discover two VLAN-20 hosts; skipping same-VLAN ping test"
fi

# ---------------------------------------------------------------------------
# Cross-VLAN isolation
# ---------------------------------------------------------------------------
section "Cross-VLAN isolation"

if [ "${#VLAN10_HOSTS[@]}" -ge 1 ] && [ "${#VLAN20_HOSTS[@]}" -ge 1 ]; then
    NS1="${VLAN10_HOSTS[0]%%:*}"
    IP2="${VLAN20_HOSTS[0]##*:}"
    LOSS=$(ping_loss "$NS1" "$IP2" 3)
    if [ "${LOSS:-100}" -eq 100 ]; then
        pass "Cross-VLAN: VLAN10 host cannot reach VLAN20 host ($IP2) — isolation working"
    else
        fail "Cross-VLAN: VLAN10 host can reach VLAN20 host ($IP2) — isolation BROKEN"
    fi
else
    info "Skipping cross-VLAN isolation check (hosts not found)"
fi

# ---------------------------------------------------------------------------
# 802.1Q tags in trunk capture
# ---------------------------------------------------------------------------
section "802.1Q trunk tags"

if [ -n "$TRUNK_PORT" ]; then
    CAPFILE="$_WORKDIR/trunk.cap"
    tcpdump_start "$SW1_NS" "$TRUNK_PORT" "$CAPFILE" 6 ""
    sleep 1

    # Drive some traffic across the trunk to generate tagged frames
    if [ "${#VLAN10_HOSTS[@]}" -ge 2 ]; then
        NS1="${VLAN10_HOSTS[0]%%:*}"; IP1="${VLAN10_HOSTS[0]##*:}"
        NS2="${VLAN10_HOSTS[1]%%:*}"; IP2="${VLAN10_HOSTS[1]##*:}"
        ip netns exec "$NS1" ping -c 3 -W 1 "$IP2" >/dev/null 2>&1 || true
    fi
    if [ "${#VLAN20_HOSTS[@]}" -ge 2 ]; then
        NS1="${VLAN20_HOSTS[0]%%:*}"; IP1="${VLAN20_HOSTS[0]##*:}"
        NS2="${VLAN20_HOSTS[1]%%:*}"; IP2="${VLAN20_HOSTS[1]##*:}"
        ip netns exec "$NS1" ping -c 3 -W 1 "$IP2" >/dev/null 2>&1 || true
    fi
    wait "$_LAST_TCPDUMP_PID" 2>/dev/null || true

    TAGGED=$(tcpdump_tagged_icmp_count "$CAPFILE")
    if [ "${TAGGED:-0}" -gt 0 ]; then
        pass "Trunk port shows $TAGGED tagged ICMP frame(s) — 802.1Q tagging confirmed"
    else
        info "No tagged ICMP frames captured on $TRUNK_PORT (may need more traffic or tcpdump timing)"
    fi
fi

finish
