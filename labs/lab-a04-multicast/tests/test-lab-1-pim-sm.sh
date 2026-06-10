#!/usr/bin/env bash
# test-lab-1-pim-sm.sh — verify Lab A04 multicast-1 (FRR pimd PIM-SM).
#
# Checks that:
#   - ip_forward AND mc_forwarding are both enabled in the router namespace
#   - PIM is enabled on both router interfaces (objective: pimd is configured)
#   - An IGMP group (224.x.x.x) is joined in the receiver namespace (mechanism)
#   - The kernel mroute table has an (S,G) entry (mechanism: traffic is flowing)
#
# NOTE: The iperf streaming exercise is in the walkthrough. This checker
# requires the reader to have started the iperf receiver (IGMP join) before
# running. The (S,G) entry requires an active stream to be flowing.
#
# VERIFY-ONLY / NON-DESTRUCTIVE.
#
# Run:  ./tests/multicast/test.sh 1

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

require_cmds ip jq vtysh

MCAST_GROUP="${MCAST_GROUP:-239.1.1.1}"

# ---------------------------------------------------------------------------
# Discover topology
# ---------------------------------------------------------------------------
section "Topology discovery"

# The router namespace: has ip_forward=1 AND mc_forwarding=1
ROUTER_NS=""
for ns in $(ns_list); do
    fwd=$(ns_sysctl "$ns" net.ipv4.ip_forward 2>/dev/null || echo 0)
    mcf=$(ns_sysctl "$ns" net.ipv4.conf.all.mc_forwarding 2>/dev/null || echo 0)
    if [ "$fwd" = "1" ] && [ "$mcf" = "1" ]; then
        ROUTER_NS="$ns"
        break
    fi
done

if [ -z "$ROUTER_NS" ]; then
    die "No namespace has both ip_forward=1 and mc_forwarding=1. Set sysctls in the router namespace first."
fi

info "Router namespace: $ROUTER_NS"

# End hosts: namespaces that are NOT the router and have a default route
HOST_NS=()
for ns in $(ns_list); do
    [ "$ns" = "$ROUTER_NS" ] && continue
    if ip -n "$ns" route show default 2>/dev/null | grep -q via; then
        HOST_NS+=("$ns")
    fi
done
info "Host namespaces: ${HOST_NS[*]:-none found}"

# ---------------------------------------------------------------------------
# Part A — Kernel sysctls (prerequisite for multicast forwarding)
# ---------------------------------------------------------------------------
section "Part A — Multicast forwarding sysctls"

fwd=$(ns_sysctl "$ROUTER_NS" net.ipv4.ip_forward)
if [ "$fwd" = "1" ]; then
    pass "$ROUTER_NS: net.ipv4.ip_forward=1"
else
    fail "$ROUTER_NS: net.ipv4.ip_forward=$fwd (must be 1)"
fi

mcf=$(ns_sysctl "$ROUTER_NS" net.ipv4.conf.all.mc_forwarding)
if [ "$mcf" = "1" ]; then
    pass "$ROUTER_NS: net.ipv4.conf.all.mc_forwarding=1"
else
    fail "$ROUTER_NS: net.ipv4.conf.all.mc_forwarding=$mcf (must be 1 for multicast forwarding)"
fi

# ---------------------------------------------------------------------------
# Part B — FRR pimd is running (objective)
# ---------------------------------------------------------------------------
section "Part B — FRR pimd is running"

if frr_socket_ready "$ROUTER_NS"; then
    pass "$ROUTER_NS: FRR socket ready"
    if frr_daemon_running "$ROUTER_NS" pimd; then
        pass "$ROUTER_NS: pimd process running"
    else
        fail "$ROUTER_NS: pimd not running — enable pimd=yes in /etc/frr/$ROUTER_NS/daemons and restart frr@$ROUTER_NS"
    fi
else
    fail "$ROUTER_NS: FRR socket not found — is frr@$ROUTER_NS running?"
fi

# ---------------------------------------------------------------------------
# Part C — PIM enabled on router interfaces (mechanism)
# ---------------------------------------------------------------------------
section "Part C — PIM enabled on router interfaces"

pim_ifaces=$(ip netns exec "$ROUTER_NS" vtysh -N "$ROUTER_NS" -c 'show ip pim interface json' 2>/dev/null | \
             jq -r 'to_entries[] | select(.value.pimEnabled? == true) | .key' 2>/dev/null)

if [ -n "$pim_ifaces" ]; then
    iface_count=$(echo "$pim_ifaces" | wc -l)
    pass "$ROUTER_NS: PIM enabled on $iface_count interface(s): $(echo $pim_ifaces | tr '\n' ' ')"
    if [ "$iface_count" -ge 2 ]; then
        pass "$ROUTER_NS: PIM on ≥2 interfaces (both upstream and downstream covered)"
    else
        fail "$ROUTER_NS: PIM on only $iface_count interface — enable on both src-facing and dst-facing interfaces"
    fi
else
    fail "$ROUTER_NS: no interfaces with PIM enabled — configure 'ip pim' on each interface in vtysh"
fi

# ---------------------------------------------------------------------------
# Part D — IGMP group joined by a receiver (mechanism: shows IGMP query/report)
# ---------------------------------------------------------------------------
section "Part D — IGMP group join in FRR and kernel"

igmp_groups=$(ip netns exec "$ROUTER_NS" vtysh -N "$ROUTER_NS" -c 'show ip igmp groups json' 2>/dev/null | \
              jq -r '.. | strings | select(test("^2[0-9]{2}\\."))' 2>/dev/null | head -5)

if [ -n "$igmp_groups" ]; then
    pass "$ROUTER_NS: IGMP group(s) joined: $(echo $igmp_groups | tr '\n' ' ')"
else
    info "$ROUTER_NS: no IGMP groups in pimd table — start the iperf receiver (it sends IGMP join) then re-run"
fi

# Check kernel maddr table on host namespaces
for ns in "${HOST_NS[@]}"; do
    if ip -n "$ns" maddr show 2>/dev/null | grep -qiE "239\.|224\."; then
        joined_grp=$(ip -n "$ns" maddr show 2>/dev/null | grep -oiE "239\.[0-9.]+|224\.[0-9.]+" | head -1)
        pass "$ns: kernel multicast membership visible ($joined_grp) — IGMP join sent"
    else
        info "$ns: no multicast group membership in kernel — run iperf receiver first"
    fi
done

# ---------------------------------------------------------------------------
# Part E — (S,G) entry in kernel mroute (mechanism: traffic is flowing)
# ---------------------------------------------------------------------------
section "Part E — Kernel multicast route table has (S,G) entry"

mroute_out=$(ip netns exec "$ROUTER_NS" ip mroute show 2>/dev/null)
if [ -n "$mroute_out" ]; then
    pass "$ROUTER_NS: kernel mroute table has entries:"
    echo "$mroute_out" | while IFS= read -r line; do info "  $line"; done
    # Also check FRR's view
    frr_mroute=$(ip netns exec "$ROUTER_NS" vtysh -N "$ROUTER_NS" -c 'show ip mroute' 2>/dev/null | \
                 grep -v '^$' | head -10)
    if [ -n "$frr_mroute" ]; then
        pass "$ROUTER_NS: FRR also shows mroute entries"
    else
        info "$ROUTER_NS: FRR mroute table empty (check 'show ip mroute' in vtysh after starting iperf)"
    fi
else
    fail "$ROUTER_NS: kernel mroute table is empty — start an iperf stream from src and an iperf receiver on dst, then re-run"
fi

finish
