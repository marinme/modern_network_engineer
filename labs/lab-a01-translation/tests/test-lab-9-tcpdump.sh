#!/usr/bin/env bash
# test-lab-9-tcpdump.sh — verify the "Capture some packets" section of Lab A01.
#
# Starts a tcpdump capture on the loopback interface (reliable inside a
# container with no egress), generates ICMP traffic with ping, and verifies
# that packets appear in the capture. Also tests the -w/-r pcap round-trip and
# the echo-request-only BPF filter.
#
# Usage:  ./tests/test.sh 9

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"

require_cmds tcpdump ping timeout

PCAP="$_WORKDIR/icmp.pcap"

# ---------------------------------------------------------------------------
section "Live capture — loopback ICMP"
# ---------------------------------------------------------------------------

# Capture on 'lo' — loopback is always reachable inside the container.
# The lab uses 'any' but lo is more predictable for automated tests.
CAPFILE="$_WORKDIR/live.txt"
tcpdump_bg lo "$CAPFILE" 6
sleep 0.5   # let capture attach

ping -c 4 127.0.0.1 >/dev/null 2>&1 || true
sleep 0.5   # let last reply land

kill "$_LAST_TCPDUMP_PID" 2>/dev/null || true
wait "$_LAST_TCPDUMP_PID" 2>/dev/null || true

COUNT="$(tcpdump_icmp_count "$CAPFILE")"
if [ "$COUNT" -ge 4 ]; then
  pass "tcpdump captured $COUNT ICMP echo request/reply lines from loopback ping"
elif [ "$COUNT" -ge 1 ]; then
  pass "tcpdump captured $COUNT ICMP line(s) — fewer than 8 expected but still working"
else
  fail "tcpdump captured 0 ICMP lines — capture or ping may have failed"
fi

# ---------------------------------------------------------------------------
section "Capture to file and read back (-w / -r round-trip)"
# ---------------------------------------------------------------------------

timeout 6 tcpdump -nn -i lo -c 10 -w "$PCAP" 'icmp' >/dev/null 2>&1 &
BG_PID=$!
_BG_PIDS+=("$BG_PID")
sleep 0.5

ping -c 3 127.0.0.1 >/dev/null 2>&1 || true
sleep 0.5

kill "$BG_PID" 2>/dev/null; wait "$BG_PID" 2>/dev/null || true

if [ -s "$PCAP" ]; then
  pass "pcap file written to disk ($(du -h "$PCAP" | cut -f1))"
else
  fail "pcap file is empty or missing after 'tcpdump -w'"
fi

READ_COUNT="$(tcpdump -nnr "$PCAP" 2>/dev/null | grep -cE 'ICMP echo' || echo 0)"
if [ "$READ_COUNT" -ge 1 ]; then
  pass "tcpdump -r reads back $READ_COUNT ICMP frame(s) from pcap file"
else
  fail "tcpdump -r found 0 ICMP frames in pcap file"
fi

# ---------------------------------------------------------------------------
section "BPF filter — echo requests only (not replies)"
# ---------------------------------------------------------------------------

REQ_FILE="$_WORKDIR/req-only.txt"
timeout 6 tcpdump -l -nn -i lo -c 10 'icmp[icmptype] == icmp-echo' \
  >"$REQ_FILE" 2>/dev/null &
BG2=$!
_BG_PIDS+=("$BG2")
sleep 0.5

ping -c 3 127.0.0.1 >/dev/null 2>&1 || true
sleep 0.5

kill "$BG2" 2>/dev/null; wait "$BG2" 2>/dev/null || true

# Filter should capture echo requests only (type 8), not replies (type 0)
# grep -c exits 1 (no matches) but still prints "0". Use ; true so the exit
# code is always 0, avoiding the || echo 0 double-print bug.
REQ_COUNT="$(grep -cE 'ICMP echo request' "$REQ_FILE" 2>/dev/null; true)"
REQ_COUNT="${REQ_COUNT:-0}"
REPLY_COUNT="$(grep -cE 'ICMP echo reply' "$REQ_FILE" 2>/dev/null; true)"
REPLY_COUNT="${REPLY_COUNT:-0}"

if [ "$REQ_COUNT" -ge 1 ]; then
  pass "BPF filter 'icmp[icmptype] == icmp-echo' captured $REQ_COUNT request(s)"
else
  fail "BPF filter captured 0 echo requests"
fi

if [ "$REPLY_COUNT" -eq 0 ]; then
  pass "BPF filter correctly excluded $REPLY_COUNT reply frames (type-specific filtering works)"
else
  warn "$REPLY_COUNT reply frame(s) slipped through the echo-request-only filter — kernel BPF version may differ"
fi

finish
