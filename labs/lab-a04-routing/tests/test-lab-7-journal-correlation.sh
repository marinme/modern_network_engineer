#!/usr/bin/env bash
# test-lab-7-journal-correlation.sh — verify Lab A04-7 (journal correlation).
#
# Checks that:
#   - frr@* systemd units have journal entries (FRR is logging via journald)
#   - The kernel also has journal entries (dmesg events visible via journalctl -k)
#   - journalctl -o json-pretty produces parseable JSON output
#   - A structured jq query can interleave both FRR and kernel entries
#
# NOTE: This checker does NOT flap links. The three-shell exercise (flap a veth,
# watch both writers log the event) is the reader's hands-on task. This script
# confirms the infrastructure is in place for that exercise to work.
#
# VERIFY-ONLY / NON-DESTRUCTIVE.
#
# Run:  ./tests/routing/test.sh 7

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

require_cmds ip jq journalctl

# ---------------------------------------------------------------------------
# Discover topology
# ---------------------------------------------------------------------------
section "Topology discovery"

FRR_NS=()
for ns in $(ns_list); do
    frr_socket_ready "$ns" && FRR_NS+=("$ns")
done

[ "${#FRR_NS[@]}" -gt 0 ] || die "No FRR instances found. Run /lab/setup.sh first."

info "FRR namespaces: ${FRR_NS[*]}"

# ---------------------------------------------------------------------------
# Part A — systemd journal is accessible
# ---------------------------------------------------------------------------
section "Part A — journalctl is available and functional"

if command -v journalctl >/dev/null 2>&1; then
    pass "journalctl is available"
else
    die "journalctl not found — this container must run systemd as PID 1"
fi

if journalctl -n 1 --no-pager -q 2>/dev/null | grep -q .; then
    pass "journalctl returns journal entries"
else
    fail "journalctl returns no entries — is systemd running? (check: systemctl is-system-running)"
fi

# ---------------------------------------------------------------------------
# Part B — FRR units have journal entries (FRR is logging via journald)
# ---------------------------------------------------------------------------
section "Part B — frr@* units logging to journal"

frr_units_found=0
for ns in "${FRR_NS[@]}"; do
    unit="frr@${ns}.service"
    if journal_unit_has_entries "$unit"; then
        pass "$unit: has journal entries (journalctl -u $unit works)"
        frr_units_found=$(( frr_units_found + 1 ))
    else
        fail "$unit: no journal entries found — FRR may not be logging via syslog/journald"
    fi
done

if [ "$frr_units_found" -gt 0 ]; then
    pass "$frr_units_found of ${#FRR_NS[@]} frr@* unit(s) have journal entries"
else
    fail "No frr@* units found in journal — is FRR running and using systemd logging?"
fi

# Show a sample entry for reference
journalctl -u 'frr@*' -n 3 --no-pager 2>/dev/null | \
    while IFS= read -r line; do info "  $line"; done || true

# ---------------------------------------------------------------------------
# Part C — Kernel has journal entries (kernel events visible via -k)
# ---------------------------------------------------------------------------
section "Part C — Kernel events in journal (journalctl -k)"

if journal_kernel_has_entries; then
    pass "Kernel has journal entries (journalctl -k returns output)"
    journalctl -k -n 3 --no-pager 2>/dev/null | \
        while IFS= read -r line; do info "  $line"; done || true
else
    fail "No kernel journal entries — link events won't appear in journalctl -k"
fi

# ---------------------------------------------------------------------------
# Part D — json-pretty output is parseable by jq (structured query works)
# ---------------------------------------------------------------------------
section "Part D — Structured JSON output and jq filtering"

if journal_json_query_works; then
    pass "journalctl -o json-pretty produces parseable JSON"
else
    fail "journalctl -o json-pretty is not producing parseable JSON (jq failed)"
fi

# Run the actual cross-writer query from the article
info "Running cross-writer query (frr@r1.service OR kernel, last 2 min):"
result=$(journalctl --since '2 min ago' \
    -o json-pretty --no-pager 2>/dev/null | \
    jq -c 'select(._SYSTEMD_UNIT == "frr@r1.service" or .SYSLOG_IDENTIFIER == "kernel")
           | {t: .__REALTIME_TIMESTAMP, u: ._SYSTEMD_UNIT, m: .MESSAGE}' \
    2>/dev/null | head -5)

if [ -n "$result" ]; then
    pass "Cross-writer jq query returns interleaved entries"
    echo "$result" | while IFS= read -r line; do info "  $line"; done
else
    info "No frr@r1.service or kernel entries in the last 2 minutes (flap a link to generate events, then re-run)"
fi

# ---------------------------------------------------------------------------
# Part E — The three writers can be distinguished in the same query
# ---------------------------------------------------------------------------
section "Part E — Multiple writers visible in journal"

# Count distinct units/identifiers in recent journal output
distinct_writers=$(journalctl -n 50 --no-pager -o json-pretty 2>/dev/null | \
    jq -r '._SYSTEMD_UNIT // .SYSLOG_IDENTIFIER // "unknown"' 2>/dev/null | \
    sort -u | wc -l)

if [ "${distinct_writers:-0}" -ge 2 ]; then
    pass "Journal shows $distinct_writers distinct writers (FRR + kernel + systemd visible)"
else
    info "Only $distinct_writers distinct writer(s) visible in recent journal — generate more events by running the three-shell exercise"
fi

finish
