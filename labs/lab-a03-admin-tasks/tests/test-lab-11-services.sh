#!/usr/bin/env bash
# test-lab-11-services.sh — verify Lab A03-11 (chrony NTP, rsyslog TCP, lldpd).
#
# Part A: polls chronyc sources for a selected (*) source (up to 20 s).
# Part B: checks /tmp/syslog-collected.log for the injected token.
# Part C: queries lldpcli on each nodeA/nodeB socket for a neighbor.
#
# Run:  ./tests/test.sh 11

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

require_cmds ip

# ---------------------------------------------------------------------------
# Part A — Chrony NTP
# ---------------------------------------------------------------------------
section "Part A — Chrony NTP (offline stratum)"

# Find a namespace running chrony (ntpc/ntps pattern)
NTPC_NS=""
for ns in $(ns_list); do
    if ip netns exec "$ns" chronyc sources 2>/dev/null | grep -q '^\^'; then
        NTPC_NS="$ns"
        break
    fi
done

if [ -n "$NTPC_NS" ]; then
    if retry 20 ip netns exec "$NTPC_NS" chronyc sources 2>/dev/null | grep -q '^\*'; then
        SOURCE_LINE=$(ip netns exec "$NTPC_NS" chronyc sources 2>/dev/null | grep '^\*')
        pass "Chrony client $NTPC_NS has a selected source: $SOURCE_LINE"

        # Check stratum (should be 11 if server is stratum 10)
        STRATUM=$(ip netns exec "$NTPC_NS" chronyc tracking 2>/dev/null | \
                  grep -i stratum | head -1 | awk '{print $NF}')
        if [ -n "$STRATUM" ]; then
            pass "Chrony tracking: stratum $STRATUM"
        fi
    else
        fail "Chrony client $NTPC_NS has no selected source after 20s — check server config"
    fi
else
    info "No chrony client namespace found — run: ip netns exec ntpc chronyc sources"
    info "Build Part A first, or wait a few seconds for initial sync"
fi

# ---------------------------------------------------------------------------
# Part B — rsyslog TCP forwarding
# ---------------------------------------------------------------------------
section "Part B — rsyslog TCP syslog forwarding"

LOG_FILE="/tmp/syslog-collected.log"
TOKEN="hello from log namespace"

if [ -f "$LOG_FILE" ]; then
    if rsyslog_received "$LOG_FILE" "$TOKEN"; then
        pass "Syslog collector at $LOG_FILE contains injected token"
    else
        # Try re-injecting
        LOG_NS=""
        for ns in $(ns_list); do
            if ip -n "$ns" addr show 2>/dev/null | grep -q '10\.20\.0\.1'; then
                LOG_NS="$ns"
                break
            fi
        done

        if [ -n "$LOG_NS" ]; then
            ip netns exec "$LOG_NS" logger -t testapp "$TOKEN" 2>/dev/null || true
            sleep 2
            if rsyslog_received "$LOG_FILE" "$TOKEN"; then
                pass "Syslog collector contains injected token (after re-inject)"
            else
                fail "Syslog collector does not contain '$TOKEN'"
            fi
        else
            fail "Log file exists but token not found; re-inject with: ip netns exec log logger -t testapp '$TOKEN'"
        fi
    fi
else
    info "Collector file $LOG_FILE not found — start socat first (Part B)"
    info "Run: ip netns exec collect socat -u TCP-LISTEN:514,reuseaddr,fork OPEN:/tmp/syslog-collected.log,creat,append &"
fi

# ---------------------------------------------------------------------------
# Part C — LLDP neighbor discovery
# ---------------------------------------------------------------------------
section "Part C — LLDP neighbor discovery"

SOCKET_A="/run/lldpd-a.socket"
SOCKET_B="/run/lldpd-b.socket"

NODE_A=""
NODE_B=""
for ns in $(ns_list); do
    if ip netns exec "$ns" test -S "$SOCKET_A" 2>/dev/null; then
        NODE_A="$ns"
    fi
    if ip netns exec "$ns" test -S "$SOCKET_B" 2>/dev/null; then
        NODE_B="$ns"
    fi
done

# Also check the host namespace for the sockets
[ -S "$SOCKET_A" ] && NODE_A="host"
[ -S "$SOCKET_B" ] && NODE_B="host"

if [ -n "$NODE_A" ] || [ -n "$NODE_B" ]; then
    # Try to discover which ns holds the sockets
    for ns in nodeA nodeB $(ns_list); do
        if [ "$ns" = "nodeA" ] || [ "$ns" = "nodeB" ]; then
            # These are canonical names from the lab
            NS_CANDIDATE="$ns"
        else
            NS_CANDIDATE="$ns"
        fi
        break
    done

    # Check lldpd socket and query via lldpcli
    if [ -S "$SOCKET_A" ]; then
        NEIGHS=$(lldpcli -u "$SOCKET_A" show neighbors 2>/dev/null | grep -c 'ChassisID\|Interface' || true)
        if [ "${NEIGHS:-0}" -gt 0 ]; then
            pass "nodeA (socket $SOCKET_A) has LLDP neighbors"
        else
            if retry 10 sh -c "lldpcli -u $SOCKET_A show neighbors 2>/dev/null | grep -q 'ChassisID'"; then
                pass "nodeA has LLDP neighbors (after poll)"
            else
                fail "nodeA ($SOCKET_A) reports no LLDP neighbors after 10s"
            fi
        fi
    else
        info "LLDP socket $SOCKET_A not found — start lldpd in nodeA first"
    fi

    if [ -S "$SOCKET_B" ]; then
        NEIGHS=$(lldpcli -u "$SOCKET_B" show neighbors 2>/dev/null | grep -c 'ChassisID\|Interface' || true)
        if [ "${NEIGHS:-0}" -gt 0 ]; then
            pass "nodeB (socket $SOCKET_B) has LLDP neighbors"
        else
            if retry 10 sh -c "lldpcli -u $SOCKET_B show neighbors 2>/dev/null | grep -q 'ChassisID'"; then
                pass "nodeB has LLDP neighbors (after poll)"
            else
                fail "nodeB ($SOCKET_B) reports no LLDP neighbors after 10s"
            fi
        fi
    else
        info "LLDP socket $SOCKET_B not found — start lldpd in nodeB first"
    fi
else
    info "Neither LLDP socket ($SOCKET_A, $SOCKET_B) found — build Part C first"
fi

finish
