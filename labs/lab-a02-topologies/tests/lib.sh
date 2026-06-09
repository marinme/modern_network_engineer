#!/usr/bin/env bash
# lib.sh — shared helpers for the Lab A02 verification scripts.
#
# Sourced by the per-lab test scripts (test-lab-N-*.sh). Everything here is
# read-only against the live network namespaces: it inspects state with
# `ip`/`sysctl -n`, sends ICMP with `ping`, and sniffs passively with
# `tcpdump`. It never creates, deletes, or reconfigures anything, so it is
# safe to run against a topology you built by hand.
#
# Conventions:
#   - `set -uo pipefail` (NOT -e): we want to run every check and report all
#     results, so individual failures must not abort the script.
#   - Each check calls `pass` or `fail`; `finish` exits 0 iff nothing failed.

set -uo pipefail

# ---------------------------------------------------------------------------
# Output + scoring
# ---------------------------------------------------------------------------

if [ -t 1 ]; then
  _C_GREEN=$'\033[32m'; _C_RED=$'\033[31m'; _C_YEL=$'\033[33m'
  _C_BLU=$'\033[34m';   _C_DIM=$'\033[2m';  _C_RST=$'\033[0m'
else
  _C_GREEN=''; _C_RED=''; _C_YEL=''; _C_BLU=''; _C_DIM=''; _C_RST=''
fi

_PASS=0
_FAIL=0

pass() { _PASS=$((_PASS + 1)); printf '%s  PASS%s  %s\n' "$_C_GREEN" "$_C_RST" "$*"; }
fail() { _FAIL=$((_FAIL + 1)); printf '%s  FAIL%s  %s\n' "$_C_RED"   "$_C_RST" "$*"; }
info() { printf '%s  ..  %s%s\n' "$_C_DIM" "$*" "$_C_RST"; }
warn() { printf '%s  WARN%s  %s\n' "$_C_YEL" "$_C_RST" "$*"; }
section() { printf '\n%s%s%s\n' "$_C_BLU" "$*" "$_C_RST"; }

# summary — print the tally. finish — exit with a status reflecting failures.
summary() {
  local total=$((_PASS + _FAIL))
  printf '\n%s%d/%d checks passed%s\n' \
    "$([ "$_FAIL" -eq 0 ] && printf '%s' "$_C_GREEN" || printf '%s' "$_C_RED")" \
    "$_PASS" "$total" "$_C_RST"
}
finish() { summary; [ "$_FAIL" -eq 0 ]; exit $?; }

# die — unrecoverable setup error (missing tool, etc.); distinct from a check FAIL.
die() { printf '%sERROR:%s %s\n' "$_C_RED" "$_C_RST" "$*" >&2; exit 2; }

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

# require_cmds CMD... — die if any command is missing from PATH.
require_cmds() {
  local missing=() c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    die "missing required command(s): ${missing[*]} (run this inside the article-02 container)"
  fi
}

# ---------------------------------------------------------------------------
# Temp workspace + background-process cleanup
# ---------------------------------------------------------------------------

_WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/lab-a02-test.XXXXXX")"
_BG_PIDS=()

_cleanup() {
  local p
  for p in "${_BG_PIDS[@]:-}"; do
    [ -n "$p" ] && kill "$p" 2>/dev/null || true
  done
  rm -rf "$_WORKDIR" 2>/dev/null || true
}
trap _cleanup EXIT INT TERM

# ---------------------------------------------------------------------------
# Read-only namespace introspection (prefers `ip -j` JSON + jq)
# ---------------------------------------------------------------------------

# ns_list — named network namespaces, one per line.
ns_list() {
  ip -j netns list 2>/dev/null | jq -r '.[].name' 2>/dev/null \
    || ip netns list 2>/dev/null | awk 'NF{print $1}'
}

# ns_forwarding NS — print the namespace's net.ipv4.ip_forward value (0/1), or empty.
ns_forwarding() {
  ip netns exec "$1" sysctl -n net.ipv4.ip_forward 2>/dev/null
}

# ns_connected_v4 NS — connected IPv4 subnets in NS, one per line as: "<subnet> <dev> <ip>"
# Derived from kernel-installed link-scope routes joined to the interface address.
# Example line:  10.0.0.0/24 veth-r1a 10.0.0.254
ns_connected_v4() {
  local ns="$1"
  # route show: connected v4 routes are proto kernel + scope link, with a prefsrc.
  ip -j -n "$ns" route show 2>/dev/null | jq -r '
    .[]
    | select(.dst != "default")
    | select((.protocol // "") == "kernel")
    | select((.scope // "") == "link")
    | select(.gateway == null)
    | select(.prefsrc != null)
    | select(.dst | test(":") | not)            # IPv4 only
    | "\(.dst) \(.dev) \(.prefsrc)"
  ' 2>/dev/null
}

# ns_route_nexthop NS DST — how NS would reach DST: prints "<gateway> <dev>".
# gateway is "-" for an on-link (directly connected) destination.
ns_route_nexthop() {
  local ns="$1" dst="$2"
  ip -j -n "$ns" route get "$dst" 2>/dev/null | jq -r '
    .[0] | "\(.gateway // "-") \(.dev // "-")"
  ' 2>/dev/null
}

# ---------------------------------------------------------------------------
# Active probes
# ---------------------------------------------------------------------------

# ping_ok SRC_NS DST_IP [count] — return 0 if at least one reply came back.
ping_ok() {
  local ns="$1" dst="$2" count="${3:-3}"
  ip netns exec "$ns" ping -c "$count" -W 1 -n "$dst" >/dev/null 2>&1
}

# ping_loss SRC_NS DST_IP [count] — print integer packet-loss percentage (best effort).
ping_loss() {
  local ns="$1" dst="$2" count="${3:-3}"
  ip netns exec "$ns" ping -c "$count" -W 1 -n "$dst" 2>/dev/null \
    | grep -oE '[0-9]+% packet loss' | grep -oE '^[0-9]+' | head -n1
}

# tcpdump_start NS IFACE OUTFILE [secs] — begin a bounded passive ICMP capture in the
# background, writing packet lines to OUTFILE. Sets _LAST_TCPDUMP_PID and records it in
# _BG_PIDS for trap cleanup. Returns immediately; the caller drives the traffic, then
# kills/waits on the pid before counting.
# Optional 5th arg EXTRA is passed verbatim to tcpdump (e.g. "-e" to print the
# link-layer header so 802.1Q VLAN tags show up). Intentionally word-split.
_LAST_TCPDUMP_PID=""
tcpdump_start() {
  local ns="$1" iface="$2" out="$3" secs="${4:-6}" extra="${5:-}"
  # -l line-buffer (so packets hit OUTFILE promptly); -nn no name/port resolution;
  # -c 50 caps packets; `timeout` is a wall-clock backstop if traffic is sparse.
  # shellcheck disable=SC2086  # $extra must word-split into separate flags
  timeout "$secs" ip netns exec "$ns" tcpdump -l -nn $extra -c 50 -i "$iface" 'icmp' \
    >"$out" 2>/dev/null &
  _LAST_TCPDUMP_PID=$!
  _BG_PIDS+=("$_LAST_TCPDUMP_PID")
}

# tcpdump_icmp_count OUTFILE — count ICMP echo request/reply lines in a capture file.
# Always prints exactly one integer (0 when the file is empty or missing).
tcpdump_icmp_count() {
  local n
  n="$(grep -cE 'ICMP echo (request|reply)' "$1" 2>/dev/null)" || n=0
  printf '%s\n' "${n:-0}"
}

# tcpdump_tagged_icmp_count OUTFILE — count ICMP echo lines that carry an 802.1Q tag
# (capture must have been taken with `-e`). Single integer.
tcpdump_tagged_icmp_count() {
  local n
  n="$(grep -cE 'vlan [0-9]+,.*ICMP echo (request|reply)' "$1" 2>/dev/null)" || n=0
  printf '%s\n' "${n:-0}"
}

# tcpdump_first_vlan OUTFILE — VLAN id of the first tagged frame in the capture (empty
# if none). Used to prove two VLANs ride the trunk under *different* tags.
tcpdump_first_vlan() {
  grep -oE 'vlan [0-9]+' "$1" 2>/dev/null | head -n1 | grep -oE '[0-9]+'
}

# ---------------------------------------------------------------------------
# Bridge / VLAN introspection (read-only)
# ---------------------------------------------------------------------------

# ns_bridges NS — bridge device names in NS, one per line.
ns_bridges() {
  ip -j -n "$1" link show type bridge 2>/dev/null | jq -r '.[].ifname' 2>/dev/null
}

# ns_bridge_ports NS BR — ifnames enslaved to bridge BR in NS, one per line.
ns_bridge_ports() {
  ip -j -n "$1" link show master "$2" 2>/dev/null | jq -r '.[].ifname' 2>/dev/null
}

# ns_vlan_filtering NS BR — print 1 if bridge BR has VLAN filtering on, else 0.
ns_vlan_filtering() {
  ip -d -j -n "$1" link show "$2" 2>/dev/null \
    | jq -r '.[0].linkinfo.info_data.vlan_filtering // 0' 2>/dev/null
}

# ns_iface_kind NS IFACE — link kind: "bridge" | "veth" | "vlan" | "" (plain/unknown).
ns_iface_kind() {
  ip -d -j -n "$1" link show "$2" 2>/dev/null \
    | jq -r '.[0].linkinfo.info_kind // ""' 2>/dev/null
}

# ns_iface_mac NS IFACE — MAC address of IFACE in NS (lowercased), empty if none.
ns_iface_mac() {
  ip -j -n "$1" link show "$2" 2>/dev/null \
    | jq -r '.[0].address // ""' 2>/dev/null | tr 'A-Z' 'a-z'
}

# ns_ip_in_subnet NS SUBNET — first connected IPv4 of NS within SUBNET (empty if none).
ns_ip_in_subnet() {
  ns_connected_v4 "$1" | awk -v s="$2" '$1==s {print $3; exit}'
}

# fdb_has_mac NS BR MAC — return 0 if MAC is in BR's forwarding DB on a *port*
# (i.e. learned through the bridge, not the bridge's own address).
fdb_has_mac() {
  local ns="$1" br="$2" mac="${3,,}"
  bridge -j -n "$ns" fdb show br "$br" 2>/dev/null | jq -e --arg m "$mac" --arg br "$br" '
    any(.[]; (.mac | ascii_downcase) == $m and ((.ifname // .dev // "") != $br))
  ' >/dev/null 2>&1
}

# port_vlans NS PORT — VLAN ids configured on bridge PORT in NS, one per line.
port_vlans() {
  bridge -j -n "$1" vlan show 2>/dev/null \
    | jq -r --arg p "$2" '.[] | select(.ifname == $p) | .vlans[]?.vlan' 2>/dev/null
}
