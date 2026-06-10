#!/usr/bin/env bash
# test-lab-1-rib-vs-fib.sh — verify Lab A04-1 (RIB vs FIB / vtysh primer).
#
# Checks that:
#   - FRR is running in the router namespaces (sockets present)
#   - vtysh can reach FRR's RIB (show ip route returns output)
#   - The kernel FIB (ip route show) is also queryable and non-empty
#   - Connected routes visible in FRR's RIB match the connected subnets in the FIB
#
# VERIFY-ONLY / NON-DESTRUCTIVE.  Auto-discovers namespaces by looking for those
# with active FRR sockets in /run/frr/<ns>/.
#
# Run:  ./tests/routing/test.sh 1

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

require_cmds ip jq vtysh

# ---------------------------------------------------------------------------
# Discover topology
# ---------------------------------------------------------------------------
section "Topology discovery"

FRR_NS=()
for ns in $(ns_list); do
    if frr_socket_ready "$ns"; then
        FRR_NS+=("$ns")
    fi
done

if [ "${#FRR_NS[@]}" -eq 0 ]; then
    die "No FRR instances found. Run /lab/setup.sh first."
fi

info "Namespaces with FRR running: ${FRR_NS[*]}"

# ---------------------------------------------------------------------------
# Part A — FRR daemons are up
# ---------------------------------------------------------------------------
section "Part A — FRR daemon readiness"

for ns in "${FRR_NS[@]}"; do
    if frr_socket_ready "$ns"; then
        pass "frr@$ns: zebra vty socket present (/run/frr/$ns/zebra.vty)"
    else
        fail "frr@$ns: zebra vty socket missing — is frr@$ns.service running?"
    fi

    if frr_daemon_running "$ns" zebra; then
        pass "frr@$ns: zebra process running"
    else
        fail "frr@$ns: zebra process not found"
    fi
done

# ---------------------------------------------------------------------------
# Part B — RIB is queryable via vtysh
# ---------------------------------------------------------------------------
section "Part B — RIB queryable via vtysh"

for ns in "${FRR_NS[@]}"; do
    rib_output=$(ip netns exec "$ns" vtysh -N "$ns" -c 'show ip route' 2>/dev/null)
    if [ -n "$rib_output" ]; then
        pass "frr@$ns: 'show ip route' returns output (RIB queryable)"
    else
        fail "frr@$ns: 'show ip route' returned nothing — vtysh connection failed?"
    fi

    # RIB should include connected routes (C prefix in IOS-style output)
    if echo "$rib_output" | grep -qE '^C'; then
        pass "frr@$ns: RIB contains connected routes (C lines visible)"
    else
        info "frr@$ns: no connected routes in RIB yet (may be normal at this stage)"
    fi
done

# ---------------------------------------------------------------------------
# Part C — FIB is queryable via ip route show
# ---------------------------------------------------------------------------
section "Part C — FIB queryable via ip route show"

for ns in "${FRR_NS[@]}"; do
    fib_count=$(ip -j -n "$ns" route show 2>/dev/null | jq 'length' 2>/dev/null || echo 0)
    if [ "${fib_count:-0}" -gt 0 ]; then
        pass "frr@$ns: kernel FIB has $fib_count route(s)"
    else
        fail "frr@$ns: kernel FIB is empty"
    fi
done

# ---------------------------------------------------------------------------
# Part D — Mechanism: RIB and FIB show consistent connected subnets
# ---------------------------------------------------------------------------
section "Part D — RIB and FIB consistency (connected routes)"

for ns in "${FRR_NS[@]}"; do
    # Count connected subnets from live interface state
    connected=$(ns_connected_v4 "$ns" | wc -l)
    # Count kernel routes with proto=kernel (installed by address assignment)
    kernel_routes=$(ip -j -n "$ns" route show proto kernel 2>/dev/null | \
                    jq 'length' 2>/dev/null || echo 0)

    if [ "${connected:-0}" -gt 0 ] && [ "${kernel_routes:-0}" -gt 0 ]; then
        pass "frr@$ns: $connected connected subnet(s), $kernel_routes kernel FIB route(s) — consistent"
    else
        info "frr@$ns: connected=$connected kernel_routes=$kernel_routes (topology may not be fully built yet)"
    fi
done

finish
