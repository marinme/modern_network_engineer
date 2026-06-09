#!/usr/bin/env bash
# test-lab-7-dhcp.sh — verify Lab A03-7 (dnsmasq DHCP server + dhcrelay).
#
# Auto-discovers: lease files in /tmp/leases-*.txt.
# Part A: client veth MAC matches a lease entry in the 10.0.0.100-200 range.
# Part B: a relay-acquired lease is on the 10.1.0.x subnet (not the server subnet).
#
# Run:  ./tests/test.sh 7

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

require_cmds ip jq

# ---------------------------------------------------------------------------
# Auto-discover lease files
# ---------------------------------------------------------------------------
section "Topology discovery"

LEASE_FILES=()
for f in /tmp/leases-*.txt; do
    [ -f "$f" ] && LEASE_FILES+=("$f")
done

[ "${#LEASE_FILES[@]}" -ge 1 ] || \
    die "No dnsmasq lease files found at /tmp/leases-*.txt. Run Part A first."

info "Found ${#LEASE_FILES[@]} lease file(s): ${LEASE_FILES[*]}"

# ---------------------------------------------------------------------------
# Part A — Direct DHCP (10.0.0.0/24)
# ---------------------------------------------------------------------------
section "Part A — Direct DHCP lease"

# Find the namespace that got a DHCP address in 10.0.0.100-200
DHCPC_NS=""
DHCPC_ADDR=""
for ns in $(ns_list); do
    addrs=$(ip -j -n "$ns" addr show 2>/dev/null | \
            jq -r '.[] | .addr_info[] | select(.family=="inet" and .scope=="global") | .local' \
            2>/dev/null)
    while IFS= read -r a; do
        # Match 10.0.0.100 – 10.0.0.200
        third=$(echo "$a" | cut -d. -f3)
        fourth=$(echo "$a" | cut -d. -f4)
        if [ "$(echo "$a" | cut -d. -f1-2)" = "10.0" ] && [ "$third" = "0" ] && \
           [ "${fourth:-0}" -ge 100 ] && [ "${fourth:-0}" -le 200 ]; then
            DHCPC_NS="$ns"
            DHCPC_ADDR="$a"
            break 2
        fi
    done <<< "$addrs"
done

if [ -n "$DHCPC_NS" ]; then
    pass "DHCP client $DHCPC_NS acquired address $DHCPC_ADDR (in pool 10.0.0.100-200)"

    # Verify MAC appears in a lease file
    MAC=$(ip -j -n "$DHCPC_NS" link show 2>/dev/null | \
          jq -r '.[] | select(.ifname != "lo") | .address' 2>/dev/null | head -1)
    if [ -n "$MAC" ]; then
        MATCHED=false
        for lf in "${LEASE_FILES[@]}"; do
            if grep -qi "$MAC" "$lf" 2>/dev/null; then
                MATCHED=true
                break
            fi
        done
        if $MATCHED; then
            pass "Client MAC $MAC found in lease file"
        else
            fail "Client MAC $MAC not found in any lease file"
        fi
    fi

    # Check the server namespace has the pool address assigned
    SRV_NS=""
    for ns in $(ns_list); do
        [ "$ns" = "$DHCPC_NS" ] && continue
        if ip -j -n "$ns" addr show 2>/dev/null | \
           jq -r '.[] | .addr_info[] | select(.family=="inet") | .local' \
           2>/dev/null | grep -q '^10\.0\.0\.1$'; then
            SRV_NS="$ns"
            break
        fi
    done
    [ -n "$SRV_NS" ] && pass "dnsmasq server namespace: $SRV_NS (10.0.0.1/24 assigned)"
else
    fail "No namespace with a DHCP-acquired address in 10.0.0.100-200 found"
    info "Run: ip netns exec dhcpc dhclient -v veth-client"
fi

# ---------------------------------------------------------------------------
# Part B — Relay (10.1.0.0/24)
# ---------------------------------------------------------------------------
section "Part B — Relayed DHCP lease (10.1.0.x)"

RELAY_NS=""
RELAY_ADDR=""
for ns in $(ns_list); do
    addrs=$(ip -j -n "$ns" addr show 2>/dev/null | \
            jq -r '.[] | .addr_info[] | select(.family=="inet" and .scope=="global") | .local' \
            2>/dev/null)
    while IFS= read -r a; do
        # Match 10.1.0.100 – 10.1.0.200
        prefix=$(echo "$a" | cut -d. -f1-3)
        fourth=$(echo "$a" | cut -d. -f4)
        if [ "$prefix" = "10.1.0" ] && \
           [ "${fourth:-0}" -ge 100 ] && [ "${fourth:-0}" -le 200 ]; then
            RELAY_NS="$ns"
            RELAY_ADDR="$a"
            break 2
        fi
    done <<< "$addrs"
done

if [ -n "$RELAY_NS" ]; then
    pass "Relay DHCP client $RELAY_NS acquired address $RELAY_ADDR (on relay subnet 10.1.0.x)"

    # Verify this IP is in the lease file (Part B lease file)
    for lf in "${LEASE_FILES[@]}"; do
        if grep -q "10\.1\." "$lf" 2>/dev/null; then
            pass "Relay lease (10.1.x address) present in $lf"
            break
        fi
    done

    # Verify that r (the relay) has ip_forward=1
    for ns in $(ns_list); do
        if ip -n "$ns" addr show 2>/dev/null | grep -qE '10\.0\.0\.|10\.1\.0\.'; then
            fwd=$(ns_forwarding "$ns")
            if [ "$fwd" = "1" ]; then
                pass "Relay namespace $ns has ip_forward=1"
                break
            fi
        fi
    done
else
    info "No relay-acquired address (10.1.0.100-200) found — Part B not yet built"
fi

finish
