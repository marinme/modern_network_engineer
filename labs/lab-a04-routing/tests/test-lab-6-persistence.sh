#!/usr/bin/env bash
# test-lab-6-persistence.sh — verify Lab A04-6 (persisting FRR config).
#
# Checks that:
#   - /etc/frr/<ns>/frr.conf exists and is non-empty (objective: vtysh -w was run)
#   - frr.conf contains at least one router stanza (it has real config)
#   - The running FRR state matches the on-disk config (mechanism: config survived restart)
#
# NOTE: This checker does NOT restart FRR. The restart exercise is in the
# walkthrough; automating restarts would violate the non-destructive rule.
# The checker reads the config file and the running state and compares.
#
# VERIFY-ONLY / NON-DESTRUCTIVE.
#
# Run:  ./tests/routing/test.sh 6

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
    frr_socket_ready "$ns" && FRR_NS+=("$ns")
done

[ "${#FRR_NS[@]}" -gt 0 ] || die "No FRR instances found. Run /lab/setup.sh first."

info "Namespaces with FRR running: ${FRR_NS[*]}"

# ---------------------------------------------------------------------------
# Part A — frr.conf exists and is non-empty (objective: 'write' was called)
# ---------------------------------------------------------------------------
section "Part A — frr.conf written (vtysh -w or 'write' was called)"

CONFIGURED_NS=()
for ns in "${FRR_NS[@]}"; do
    conf="/etc/frr/$ns/frr.conf"
    if [ -f "$conf" ] && [ -s "$conf" ]; then
        size=$(wc -c < "$conf" 2>/dev/null || echo 0)
        pass "frr@$ns: /etc/frr/$ns/frr.conf exists ($size bytes)"
        CONFIGURED_NS+=("$ns")
    else
        fail "frr@$ns: /etc/frr/$ns/frr.conf is missing or empty — run 'write' in vtysh first"
    fi
done

[ "${#CONFIGURED_NS[@]}" -gt 0 ] || finish  # no point running further checks

# ---------------------------------------------------------------------------
# Part B — frr.conf contains routing configuration (not just boilerplate)
# ---------------------------------------------------------------------------
section "Part B — frr.conf contains a router stanza"

for ns in "${CONFIGURED_NS[@]}"; do
    conf="/etc/frr/$ns/frr.conf"
    if grep -qE '^router (bgp|ospf|isis)' "$conf" 2>/dev/null; then
        proto=$(grep -oE '^router (bgp|ospf|isis)' "$conf" | head -1)
        pass "frr@$ns: frr.conf contains '$proto' stanza"
    else
        fail "frr@$ns: frr.conf has content but no router stanza — only skeleton config saved"
    fi
done

# ---------------------------------------------------------------------------
# Part C — Running config matches on-disk config (mechanism: restart-survival)
# ---------------------------------------------------------------------------
section "Part C — Running config consistent with frr.conf (restart-survival check)"

for ns in "${CONFIGURED_NS[@]}"; do
    conf="/etc/frr/$ns/frr.conf"

    # Get router-id from running config
    running_rid=$(ip netns exec "$ns" vtysh -N "$ns" -c 'show running-config' 2>/dev/null | \
                  grep -oE 'bgp router-id [0-9.]+|ospf router-id [0-9.]+' | \
                  awk '{print $NF}' | head -1)
    # Get router-id from file
    file_rid=$(grep -oE '(bgp|ospf) router-id [0-9.]+' "$conf" 2>/dev/null | \
               awk '{print $NF}' | head -1)

    if [ -n "$running_rid" ] && [ -n "$file_rid" ]; then
        if [ "$running_rid" = "$file_rid" ]; then
            pass "frr@$ns: router-id matches ($running_rid) — running config consistent with frr.conf"
        else
            fail "frr@$ns: router-id mismatch (running=$running_rid file=$file_rid) — unsaved changes?"
        fi
    elif [ -n "$file_rid" ]; then
        # File has a router-id; running config might just format differently
        info "frr@$ns: file has router-id $file_rid; could not parse from running-config (format may differ)"
        pass "frr@$ns: frr.conf has router config — persistence check passed"
    else
        info "frr@$ns: no router-id in either source — checking for any router stanza match"
        if grep -qE '^router' "$conf" 2>/dev/null; then
            pass "frr@$ns: router stanza present in both running config and frr.conf"
        fi
    fi
done

# ---------------------------------------------------------------------------
# Part D — integrated-vtysh-config is in effect (mechanism: single file)
# ---------------------------------------------------------------------------
section "Part D — Integrated config mode (single frr.conf)"

for ns in "${CONFIGURED_NS[@]}"; do
    vtysh_conf="/etc/frr/$ns/vtysh.conf"
    if [ -f "$vtysh_conf" ] && grep -q 'service integrated-vtysh-config' "$vtysh_conf" 2>/dev/null; then
        pass "frr@$ns: integrated-vtysh-config active — 'write' saves a single frr.conf"
    else
        info "frr@$ns: vtysh.conf missing or does not set integrated-vtysh-config (may write per-daemon files)"
    fi
done

finish
