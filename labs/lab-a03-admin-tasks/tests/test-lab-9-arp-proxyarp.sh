#!/usr/bin/env bash
# test-lab-9-arp-proxyarp.sh — verify Lab A03-9 (PERMANENT ARP + proxy ARP).
#
# Auto-discovers:
#   Part A: any namespace with a PERMANENT neighbor entry.
#   Part B: any namespace with proxy_arp=1 and a proxy neighbor entry.
#
# Run:  ./tests/test.sh 9

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

require_cmds ip jq ping

# ---------------------------------------------------------------------------
# Part A — PERMANENT neighbor entry
# ---------------------------------------------------------------------------
section "Part A — PERMANENT static ARP entry"

PERM_NS=""
PERM_IP=""
PERM_MAC=""

for ns in $(ns_list); do
    entry=$(ip -j -n "$ns" neigh show 2>/dev/null | \
            jq -r '.[] | select(.state[] | ascii_downcase | contains("permanent")) | "\(.dst) \(.lladdr // empty)"' \
            2>/dev/null | head -1)
    if [ -n "$entry" ]; then
        PERM_NS="$ns"
        PERM_IP=$(echo "$entry" | awk '{print $1}')
        PERM_MAC=$(echo "$entry" | awk '{print $2}')
        break
    fi
done

if [ -n "$PERM_NS" ]; then
    pass "PERMANENT neighbor entry found in $PERM_NS: $PERM_IP → $PERM_MAC"

    # Verify the lladdr is a real MAC (6 hex pairs)
    if echo "$PERM_MAC" | grep -qE '^([0-9a-f]{2}:){5}[0-9a-f]{2}$'; then
        pass "PERMANENT entry has valid MAC address: $PERM_MAC"
    else
        fail "PERMANENT entry has no valid MAC (got: ${PERM_MAC:-empty})"
    fi

    # Verify ping works (uses static entry, no ARP needed)
    if ping_ok "$PERM_NS" "$PERM_IP" 3; then
        pass "$PERM_NS can ping $PERM_IP (PERMANENT neighbor works)"
    else
        fail "$PERM_NS cannot ping $PERM_IP despite PERMANENT entry"
    fi
else
    fail "No PERMANENT neighbor entry found in any namespace — build Part A first"
fi

# ---------------------------------------------------------------------------
# Part B — Proxy ARP
# ---------------------------------------------------------------------------
section "Part B — Proxy ARP"

PROXY_NS=""
PROXY_IFACE=""
PROXY_IP=""

# Find namespace with proxy_arp=1 on any interface
for ns in $(ns_list); do
    for iface in $(ip -j -n "$ns" link show 2>/dev/null | jq -r '.[].ifname' 2>/dev/null); do
        val=$(ns_sysctl "$ns" "net.ipv4.conf.$iface.proxy_arp" 2>/dev/null || echo 0)
        if [ "${val:-0}" -eq 1 ]; then
            PROXY_NS="$ns"
            PROXY_IFACE="$iface"
            break 2
        fi
    done
done

if [ -n "$PROXY_NS" ]; then
    pass "proxy_arp=1 on interface $PROXY_IFACE in namespace $PROXY_NS"

    # Check for a proxy neighbor entry
    proxy_entry=$(ip -j -n "$PROXY_NS" neigh show proxy 2>/dev/null | \
                  jq -r '.[0].dst // empty' 2>/dev/null)
    if [ -n "$proxy_entry" ]; then
        PROXY_IP="$proxy_entry"
        pass "Proxy neighbor entry for $PROXY_IP present"
    else
        # Try the text form
        proxy_text=$(ip -n "$PROXY_NS" neigh show proxy 2>/dev/null | head -1)
        if [ -n "$proxy_text" ]; then
            PROXY_IP=$(echo "$proxy_text" | awk '{print $1}')
            pass "Proxy neighbor entry: $proxy_text"
        else
            fail "No proxy neighbor entry found — run: ip -n <r> neigh add <ip> proxy dev <iface>"
        fi
    fi
else
    info "No interface with proxy_arp=1 found — Part B may not be built yet"
fi

# ---------------------------------------------------------------------------
# Proxy ARP — verify off-subnet host resolves to router's MAC
# ---------------------------------------------------------------------------
section "Proxy ARP end-to-end"

if [ -n "$PROXY_IP" ] && [ -n "$PROXY_NS" ]; then
    # Find the host namespace that is on the same side as the proxy interface
    ROUTER_MAC=$(ns_iface_mac "$PROXY_NS" "$PROXY_IFACE")

    for ns in $(ns_list); do
        [ "$ns" = "$PROXY_NS" ] && continue
        # Try to ping the proxied IP from this host
        if ping_ok "$ns" "$PROXY_IP" 3 2>/dev/null; then
            pass "$ns can reach proxy target $PROXY_IP through proxy ARP"

            # Check that the neighbor entry in the host shows the router's MAC
            SEEN_MAC=$(ns_neigh_lladdr "$ns" "$PROXY_IP")
            if [ -n "$SEEN_MAC" ] && [ -n "$ROUTER_MAC" ]; then
                if [ "${SEEN_MAC,,}" = "${ROUTER_MAC,,}" ]; then
                    pass "Host $ns resolves $PROXY_IP to router MAC $ROUTER_MAC (proxy working)"
                else
                    info "Host $ns resolves $PROXY_IP to $SEEN_MAC (router MAC is $ROUTER_MAC)"
                fi
            fi
            break
        fi
    done
fi

finish
