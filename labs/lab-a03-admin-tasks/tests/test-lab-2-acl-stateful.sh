#!/usr/bin/env bash
# test-lab-2-acl-stateful.sh — verify Lab A03-2 (stateful ACL with nftables).
#
# Auto-discovers: the namespace with a forward chain with policy=drop is the
# firewall.  Checks: ACL chain exists with drop policy, ct state rule present,
# SSH-permit rule present, blocked probe fails, allowed probe passes.
#
# Run:  ./tests/test.sh 2

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

require_cmds ip nft jq ncat ping

# ---------------------------------------------------------------------------
# Auto-discover topology
# ---------------------------------------------------------------------------
section "Topology discovery"

FW=""
for ns in $(ns_list); do
    if ip netns exec "$ns" nft list ruleset 2>/dev/null | \
       grep -qE 'hook forward.*policy drop|policy drop.*hook forward'; then
        FW="$ns"
        break
    fi
    # Also match: chain forward { ... policy drop; }
    if ip netns exec "$ns" nft list ruleset 2>/dev/null | \
       grep -qE 'policy drop'; then
        if ns_forwarding "$ns" | grep -q 1; then
            FW="$ns"
            break
        fi
    fi
done

[ -n "$FW" ] || die "No firewall namespace found (need a forward chain with policy drop)"
info "Firewall namespace: $FW"

# Find wan (no default route out, or the 172.16/192.168 end)
WAN=""
LAN_HOSTS=()
for ns in $(ns_list); do
    [ "$ns" = "$FW" ] && continue
    addrs=$(ip -j -n "$ns" addr show 2>/dev/null | \
            jq -r '.[] | .addr_info[] | select(.family=="inet" and .scope=="global") | .local' \
            2>/dev/null)
    if echo "$addrs" | grep -qE '^(172|192\.168)'; then
        WAN="$ns"
    else
        [ -n "$addrs" ] && LAN_HOSTS+=("$ns")
    fi
done

[ -n "$WAN" ] || { WAN="${LAN_HOSTS[0]:-}"; LAN_HOSTS=("${LAN_HOSTS[@]:1}"); }
info "WAN namespace: ${WAN:-unknown}"
info "LAN namespaces: ${LAN_HOSTS[*]:-none}"

# ---------------------------------------------------------------------------
# ACL ruleset checks
# ---------------------------------------------------------------------------
section "NFTables ruleset"

if ns_nft_chain_policy "$FW" filter ip forward | grep -qi drop; then
    pass "forward chain policy is drop"
else
    # Try without specifying family
    policy=$(ip netns exec "$FW" nft -j list ruleset 2>/dev/null | \
             jq -r '.nftables[] | .chain? | select(.name=="forward") | .policy // empty' \
             2>/dev/null | head -1)
    if [ "${policy,,}" = "drop" ]; then
        pass "forward chain policy is drop (via JSON)"
    else
        fail "forward chain policy is not drop (got: ${policy:-empty})"
    fi
fi

if ns_nft_has_rule "$FW" 'ct state established'; then
    pass "ct state established,related rule present"
else
    fail "ct state established,related rule is missing"
fi

# SSH permit rule (port 22, tcp dport 22, or ssh)
if ns_nft_has_rule "$FW" 'tcp dport 22|dport ssh|dport {22|port ssh'; then
    pass "SSH (tcp/22) permit rule present"
else
    info "No explicit ssh rule found — checking for 'tcp dport 22'"
    if ip netns exec "$FW" nft list ruleset 2>/dev/null | grep -qE 'dport.*22|22.*dport'; then
        pass "Port 22 rule found in ruleset"
    else
        fail "No SSH/port-22 permit rule found in forward chain"
    fi
fi

# ---------------------------------------------------------------------------
# Connectivity tests
# ---------------------------------------------------------------------------
section "Connectivity probes"

# Find a LAN host to test from
if [ "${#LAN_HOSTS[@]}" -gt 0 ]; then
    LHOST="${LAN_HOSTS[0]}"
    LADDR=$(ip -j -n "$LHOST" addr show 2>/dev/null | \
            jq -r '.[] | .addr_info[] | select(.family=="inet" and .scope=="global") | .local' \
            2>/dev/null | head -1)
    if [ -n "$LADDR" ]; then
        if ping_ok "$WAN" "$LADDR" 3 2>/dev/null; then
            fail "WAN can reach LAN host unprompted (forward chain should block uninitiated)"
        else
            pass "WAN cannot reach LAN host uninitiated (forward policy drop working)"
        fi

        if ping_ok "$LHOST" "$(ip -j -n "$WAN" addr show 2>/dev/null | jq -r '.[] | .addr_info[] | select(.family=="inet" and .scope=="global") | .local' 2>/dev/null | head -1)" 3; then
            pass "LAN can ping WAN (outbound allowed)"
        else
            info "LAN→WAN ping failed (may be intentional if only SSH is permitted)"
        fi
    fi
fi

# Verify a high-numbered port probe from WAN is refused/dropped
WAN_ADDR=$(ip -j -n "$WAN" addr show 2>/dev/null | \
           jq -r '.[] | .addr_info[] | select(.family=="inet" and .scope=="global") | .local' \
           2>/dev/null | head -1)

if [ "${#LAN_HOSTS[@]}" -gt 0 ] && [ -n "${LAN_HOSTS[0]:-}" ]; then
    SADDR=$(ip -j -n "${LAN_HOSTS[0]}" addr show 2>/dev/null | \
            jq -r '.[] | .addr_info[] | select(.family=="inet" and .scope=="global") | .local' \
            2>/dev/null | head -1)
    if [ -n "$SADDR" ]; then
        if timeout 3 ip netns exec "$WAN" ncat -zw 1 "$SADDR" 9999 2>/dev/null; then
            fail "WAN can connect to LAN:9999 (ACL should block this)"
        else
            pass "WAN cannot connect to LAN:9999 (ACL drop working)"
        fi
    fi
fi

finish
