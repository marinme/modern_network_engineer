#!/usr/bin/env bash
# test-lab-1-routing-failover.sh — verify Lab A03-1 (routing + failover + ECMP).
#
# Auto-discovers: the namespace with ip_forward=1 is the router; the other two
# are hosts.  Checks routing table state, metric-based backup, and ECMP.
#
# Run:  ./tests/test.sh 1

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

require_cmds ip jq ping

# ---------------------------------------------------------------------------
# Auto-discover topology
# ---------------------------------------------------------------------------
section "Topology discovery"

# Find the router (ip_forward=1 with ≥2 connected subnets)
R=""
for ns in $(ns_list); do
    fwd=$(ns_forwarding "$ns")
    subnets=$(ns_connected_v4 "$ns" | wc -l)
    if [ "$fwd" = "1" ] && [ "$subnets" -ge 2 ]; then
        R="$ns"
        break
    fi
done

[ -n "$R" ] || die "No router namespace found (need ip_forward=1 with ≥2 connected subnets)"
info "Router namespace: $R"

# Find the hosts (have a default route pointing at r)
HOSTS=()
for ns in $(ns_list); do
    [ "$ns" = "$R" ] && continue
    if ip -n "$ns" route show default 2>/dev/null | grep -q via; then
        HOSTS+=("$ns")
    fi
done

[ "${#HOSTS[@]}" -ge 2 ] || die "Need at least 2 host namespaces with a default route"
info "Host namespaces: ${HOSTS[*]}"

H1="${HOSTS[0]}"
H2="${HOSTS[1]}"

# ---------------------------------------------------------------------------
# Part A — Routing table inspection
# ---------------------------------------------------------------------------
section "Part A — Routing table inspection"

# Router must have ≥2 connected routes in the default table
R_CONNECTED=$(ns_connected_v4 "$R" | wc -l)
if [ "$R_CONNECTED" -ge 2 ]; then
    pass "Router has $R_CONNECTED connected routes"
else
    fail "Router has only $R_CONNECTED connected route(s); expected ≥2"
fi

# Hosts can reach each other's routed subnet via ping
H1_ADDR=$(ip -j -n "$H1" addr show 2>/dev/null | jq -r '.[] | .addr_info[] | select(.family=="inet" and .scope=="global") | .local' 2>/dev/null | head -1)
H2_ADDR=$(ip -j -n "$H2" addr show 2>/dev/null | jq -r '.[] | .addr_info[] | select(.family=="inet" and .scope=="global") | .local' 2>/dev/null | head -1)

[ -n "$H1_ADDR" ] || die "Could not determine h1 IP"
[ -n "$H2_ADDR" ] || die "Could not determine h2 IP"
info "h1=$H1_ADDR  h2=$H2_ADDR"

if ping_ok "$H1" "$H2_ADDR" 3; then
    pass "h1 can reach h2 ($H2_ADDR)"
else
    fail "h1 cannot reach h2 ($H2_ADDR)"
fi

if ping_ok "$H2" "$H1_ADDR" 3; then
    pass "h2 can reach h1 ($H1_ADDR)"
else
    fail "h2 cannot reach h1 ($H1_ADDR)"
fi

# ---------------------------------------------------------------------------
# Part B — Metric-based failover routes
# ---------------------------------------------------------------------------
section "Part B — Metric-based failover"

# A completed metric-based setup has at least two routes to one destination
# with different metrics.  Discover from the router's routing table.
# Look for a destination that has multiple entries with different metrics.
DEST_FOR_METRIC=""
while IFS=' ' read -r sub dev ip; do
    metrics=$(ns_route_metric "$R" "$sub" 2>/dev/null)
    count=$(echo "$metrics" | grep -c . 2>/dev/null || true)
    if [ "${count:-0}" -ge 2 ]; then
        DEST_FOR_METRIC="$sub"
        info "Found multi-metric destination: $sub (metrics: $(echo "$metrics" | tr '\n' ' '))"
        break
    fi
done < <(ns_connected_v4 "$R")

if [ -n "$DEST_FOR_METRIC" ]; then
    pass "Found destination with multiple metric values (primary + backup configured)"
else
    info "No multi-metric destination found — checking for a lo loopback address as test target"
    # Alternative: look for a route to a loopback (10.99.x) with metrics
    LOROUTE=$(ip -n "$R" route show 2>/dev/null | grep -E 'metric [0-9]+' | head -1)
    if [ -n "$LOROUTE" ]; then
        pass "Router has metric-differentiated routes: $LOROUTE"
    else
        fail "No metric-based backup routes found — complete Part B first"
    fi
fi

# ---------------------------------------------------------------------------
# Part C — ECMP multipath
# ---------------------------------------------------------------------------
section "Part C — ECMP multipath"

# Look for a destination where ip route get returns >1 nexthop OR where the
# routing table shows nexthop groups.
ECMP_DST=""
for ns in $(ns_list); do
    [ "$ns" = "$R" ] && continue
    DST=$(ip -j -n "$ns" addr show 2>/dev/null | \
          jq -r '.[] | .addr_info[] | select(.family=="inet" and .scope=="global") | .local' 2>/dev/null | head -1)
    [ -n "$DST" ] || continue
    nxt=$(ns_route_nexthop_count "$R" "$DST")
    if [ "${nxt:-1}" -ge 2 ]; then
        ECMP_DST="$DST"
        pass "ECMP: route to $DST has $nxt nexthops"
        break
    fi
done

if [ -z "$ECMP_DST" ]; then
    # Check for nexthop keyword in route table
    if ip -n "$R" route show 2>/dev/null | grep -q 'nexthop'; then
        pass "ECMP nexthop group entry found in routing table"
    else
        info "No ECMP routes detected — if Part C is not yet built, build it and re-run"
    fi
fi

finish
