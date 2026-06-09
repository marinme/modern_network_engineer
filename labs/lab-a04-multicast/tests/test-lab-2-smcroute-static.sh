#!/usr/bin/env bash
# test-lab-2-smcroute-static.sh — verify Lab A04 multicast-2 (smcroute static).
#
# Checks that:
#   - mc_forwarding is enabled in the router namespace (prerequisite)
#   - pimd is NOT running in the router namespace (this lab avoids the one-socket conflict)
#   - smcroute has installed at least one (S,G) entry in the kernel mroute table
#   - The kernel mroute table reflects the smcroute rule
#
# VERIFY-ONLY / NON-DESTRUCTIVE.
#
# Run:  ./tests/multicast/test.sh 2

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

require_cmds ip jq smcroute

# ---------------------------------------------------------------------------
# Discover topology
# ---------------------------------------------------------------------------
section "Topology discovery"

# The router: has mc_forwarding=1
ROUTER_NS=""
for ns in $(ns_list); do
    mcf=$(ns_sysctl "$ns" net.ipv4.conf.all.mc_forwarding 2>/dev/null || echo 0)
    if [ "$mcf" = "1" ]; then
        ROUTER_NS="$ns"
        break
    fi
done

[ -n "$ROUTER_NS" ] || die "No namespace with mc_forwarding=1 found. Set sysctl first."
info "Router namespace: $ROUTER_NS"

# ---------------------------------------------------------------------------
# Part A — Prerequisites
# ---------------------------------------------------------------------------
section "Part A — Prerequisites for smcroute"

mcf=$(ns_sysctl "$ROUTER_NS" net.ipv4.conf.all.mc_forwarding)
if [ "$mcf" = "1" ]; then
    pass "$ROUTER_NS: net.ipv4.conf.all.mc_forwarding=1"
else
    fail "$ROUTER_NS: mc_forwarding=$mcf"
fi

fwd=$(ns_sysctl "$ROUTER_NS" net.ipv4.ip_forward)
if [ "$fwd" = "1" ]; then
    pass "$ROUTER_NS: net.ipv4.ip_forward=1"
else
    fail "$ROUTER_NS: ip_forward=$fwd"
fi

# ---------------------------------------------------------------------------
# Part B — pimd is NOT running (one-socket constraint)
# ---------------------------------------------------------------------------
section "Part B — pimd not running (smcroute holds the mroute socket)"

if ! frr_daemon_running "$ROUTER_NS" pimd; then
    pass "$ROUTER_NS: pimd is not running — smcroute can hold the mroute socket"
else
    fail "$ROUTER_NS: pimd is running alongside smcroute — only one process can hold the mroute socket per namespace. Stop pimd first."
fi

# ---------------------------------------------------------------------------
# Part C — smcroute is running (objective)
# ---------------------------------------------------------------------------
section "Part C — smcroute daemon is running"

if ip netns exec "$ROUTER_NS" pgrep smcrouted >/dev/null 2>&1; then
    pass "$ROUTER_NS: smcrouted process running"
elif ip netns exec "$ROUTER_NS" smcroutectl show mroute 2>/dev/null | grep -q .; then
    pass "$ROUTER_NS: smcroute control socket responsive"
else
    fail "$ROUTER_NS: smcrouted not running — start with: ip netns exec $ROUTER_NS smcrouted -n"
fi

# ---------------------------------------------------------------------------
# Part D — Static (S,G) in kernel mroute table (mechanism)
# ---------------------------------------------------------------------------
section "Part D — Static (S,G) entry in kernel mroute table"

mroute_out=$(ip netns exec "$ROUTER_NS" ip mroute show 2>/dev/null)
if [ -n "$mroute_out" ]; then
    mroute_count=$(echo "$mroute_out" | grep -c . 2>/dev/null || echo 0)
    pass "$ROUTER_NS: kernel mroute table has $mroute_count entry/entries (smcroute installed them)"
    echo "$mroute_out" | while IFS= read -r line; do info "  $line"; done
else
    fail "$ROUTER_NS: kernel mroute table is empty — add a static route: smcroutectl add <src-iface> <src-ip> <group> <dst-iface>"
fi

# Check smcroute's own view if the CLI is available
smcr_mroutes=$(ip netns exec "$ROUTER_NS" smcroutectl show mroute 2>/dev/null)
if [ -n "$smcr_mroutes" ]; then
    pass "$ROUTER_NS: smcroutectl shows mroute entries"
    echo "$smcr_mroutes" | head -5 | while IFS= read -r line; do info "  $line"; done
fi

# ---------------------------------------------------------------------------
# Part E — Mroute includes outgoing interface (OIF) — traffic can flow
# ---------------------------------------------------------------------------
section "Part E — Mroute entry has an outgoing interface"

if [ -n "$mroute_out" ]; then
    # mroute show format: (src, grp)  Iif: <in> Oifs: <out>
    has_oif=$(echo "$mroute_out" | grep -E 'Oifs?:' | grep -v 'Oifs?: $' | head -1)
    if [ -n "$has_oif" ]; then
        pass "$ROUTER_NS: mroute entry has outgoing interface(s): $has_oif"
    else
        fail "$ROUTER_NS: mroute entry has no outgoing interface — smcroute rule needs both -i (in) and -o (out)"
    fi
fi

finish
