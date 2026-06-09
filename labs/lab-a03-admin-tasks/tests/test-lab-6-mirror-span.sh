#!/usr/bin/env bash
# test-lab-6-mirror-span.sh — verify Lab A03-6 (tc mirred SPAN / port mirror).
#
# Auto-discovers: the namespace with a clsact qdisc and a mirred action.
# Checks: clsact qdisc on a veth, mirred action present in filter, monitor
# interface captures copies of h1↔h2 ICMP traffic.
#
# Run:  ./tests/test.sh 6

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

require_cmds ip tc jq ping tcpdump

# ---------------------------------------------------------------------------
# Auto-discover
# ---------------------------------------------------------------------------
section "Topology discovery"

MIRROR_NS=""
MIRROR_IFACE=""
MON_IFACE=""

for ns in $(ns_list); do
    # Look for a clsact qdisc
    qdisc=$(ip netns exec "$ns" tc qdisc show 2>/dev/null | grep clsact | head -1)
    if [ -n "$qdisc" ]; then
        iface=$(echo "$qdisc" | awk '{print $5}')
        # Check for a mirred action
        if ns_tc_has_mirred "$ns" "$iface" ingress 2>/dev/null || \
           ns_tc_has_mirred "$ns" "$iface" egress 2>/dev/null; then
            MIRROR_NS="$ns"
            MIRROR_IFACE="$iface"
            break
        fi
    fi
done

[ -n "$MIRROR_NS" ] || \
    die "No namespace with a mirred tc filter found. Build the topology (lab-6-mirror-span.md) first."
info "Mirror namespace: $MIRROR_NS  mirrored interface: $MIRROR_IFACE"

# Find the dummy monitor interface (type=dummy or no assigned IPs)
for iface in $(ip -j -n "$MIRROR_NS" link show 2>/dev/null | jq -r '.[].ifname' 2>/dev/null); do
    link_type=$(ip -d -j -n "$MIRROR_NS" link show "$iface" 2>/dev/null | \
                jq -r '.[0].linkinfo.info_kind // empty' 2>/dev/null)
    if [ "$link_type" = "dummy" ]; then
        MON_IFACE="$iface"
        break
    fi
done

if [ -n "$MON_IFACE" ]; then
    info "Monitor interface: $MON_IFACE (type=dummy)"
else
    # Fall back: look for iface named mon*
    MON_IFACE=$(ip -j -n "$MIRROR_NS" link show 2>/dev/null | \
                jq -r '.[] | select(.ifname | startswith("mon")) | .ifname' 2>/dev/null | head -1)
    [ -n "$MON_IFACE" ] && info "Monitor interface (by name): $MON_IFACE"
fi

# ---------------------------------------------------------------------------
# tc filter checks
# ---------------------------------------------------------------------------
section "tc mirred filter"

if ns_tc_has_mirred "$MIRROR_NS" "$MIRROR_IFACE" ingress; then
    pass "Ingress mirred action present on $MIRROR_IFACE"
else
    fail "No ingress mirred action on $MIRROR_IFACE"
fi

if ns_tc_has_mirred "$MIRROR_NS" "$MIRROR_IFACE" egress; then
    pass "Egress mirred action present on $MIRROR_IFACE"
else
    info "No egress mirred action on $MIRROR_IFACE (only ingress mirror is also valid)"
fi

# Verify monitor interface is up
if [ -n "$MON_IFACE" ]; then
    STATE=$(ip -j -n "$MIRROR_NS" link show "$MON_IFACE" 2>/dev/null | \
            jq -r '.[0].operstate // empty' 2>/dev/null)
    if [ "${STATE,,}" = "unknown" ] || [ "${STATE,,}" = "up" ]; then
        pass "Monitor interface $MON_IFACE is up (state: $STATE)"
    else
        fail "Monitor interface $MON_IFACE is not up (state: $STATE)"
    fi
fi

# ---------------------------------------------------------------------------
# Mirror capture verification
# ---------------------------------------------------------------------------
section "Mirror capture"

if [ -z "$MON_IFACE" ]; then
    info "No monitor interface found; skipping capture test"
    finish
fi

# Find host namespaces connected to the mirrored router
H1="" H2=""
for ns in $(ns_list); do
    [ "$ns" = "$MIRROR_NS" ] && continue
    if ip -n "$ns" route show default 2>/dev/null | grep -q via; then
        if [ -z "$H1" ]; then H1="$ns"
        elif [ -z "$H2" ]; then H2="$ns"; break
        fi
    fi
done

if [ -n "$H1" ] && [ -n "$H2" ]; then
    H2_ADDR=$(ip -j -n "$H2" addr show 2>/dev/null | \
              jq -r '.[] | .addr_info[] | select(.family=="inet" and .scope=="global") | .local' \
              2>/dev/null | head -1)

    CAPFILE="$_WORKDIR/mirror.cap"
    tcpdump_start "$MIRROR_NS" "$MON_IFACE" "$CAPFILE" 8 ""
    sleep 1

    ip netns exec "$H1" ping -c 5 -W 1 "$H2_ADDR" >/dev/null 2>&1 || true
    wait "$_LAST_TCPDUMP_PID" 2>/dev/null || true

    ICMP_COUNT=$(tcpdump_icmp_count "$CAPFILE")
    if [ "${ICMP_COUNT:-0}" -gt 0 ]; then
        pass "Monitor interface captured $ICMP_COUNT ICMP frame(s) — mirror working"
    else
        fail "No ICMP frames captured on monitor interface — mirror may not be working"
        info "Capture file: $CAPFILE"
    fi
else
    info "Could not find two host namespaces; skipping capture test"
fi

finish
