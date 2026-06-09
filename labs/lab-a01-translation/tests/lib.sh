#!/usr/bin/env bash
# lib.sh — shared helpers for the Lab A01 verification scripts.
#
# Sourced by the per-lab test scripts (test-lab-N-*.sh). All helpers operate on
# the local network namespace (the container itself). No named namespaces are
# involved — Lab A01 is single-box work.
#
# Conventions:
#   - `set -uo pipefail` (NOT -e): every check runs; failures don't abort.
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

pass()    { _PASS=$((_PASS + 1)); printf '%s  PASS%s  %s\n' "$_C_GREEN" "$_C_RST" "$*"; }
fail()    { _FAIL=$((_FAIL + 1)); printf '%s  FAIL%s  %s\n' "$_C_RED"   "$_C_RST" "$*"; }
info()    { printf '%s  ..  %s%s\n' "$_C_DIM" "$*" "$_C_RST"; }
warn()    { printf '%s  WARN%s  %s\n' "$_C_YEL" "$_C_RST" "$*"; }
section() { printf '\n%s%s%s\n' "$_C_BLU" "$*" "$_C_RST"; }

summary() {
  local total=$((_PASS + _FAIL))
  printf '\n%s%d/%d checks passed%s\n' \
    "$([ "$_FAIL" -eq 0 ] && printf '%s' "$_C_GREEN" || printf '%s' "$_C_RED")" \
    "$_PASS" "$total" "$_C_RST"
}
finish() { summary; [ "$_FAIL" -eq 0 ]; exit $?; }

# die — unrecoverable setup error; distinct from a check FAIL.
die() { printf '%sERROR:%s %s\n' "$_C_RED" "$_C_RST" "$*" >&2; exit 2; }

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

require_cmds() {
  local missing=() c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
  done
  [ "${#missing[@]}" -eq 0 ] || die "missing required command(s): ${missing[*]} (run inside the article-01 container)"
}

# ---------------------------------------------------------------------------
# Temp workspace + background-process cleanup
# ---------------------------------------------------------------------------

_WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/lab-a01-test.XXXXXX")"
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
# Local-box helpers
# ---------------------------------------------------------------------------

# default_gw — print the default route gateway IP, or "" if none.
default_gw() {
  ip -j route show default 2>/dev/null | jq -r '.[0].gateway // ""' 2>/dev/null
}

# default_dev — print the default route egress interface, or "".
default_dev() {
  ip -j route show default 2>/dev/null | jq -r '.[0].dev // ""' 2>/dev/null
}

# eth0_ip — first IPv4 address on eth0, or "".
eth0_ip() {
  ip -j addr show dev eth0 2>/dev/null \
    | jq -r '[.[0].addr_info[] | select(.family=="inet")][0].local // ""' 2>/dev/null
}

# addr_on_dev DEV — list of IPv4 addresses currently assigned to DEV, one per line.
addr_on_dev() {
  ip -j addr show dev "$1" 2>/dev/null \
    | jq -r '.[0].addr_info[] | select(.family=="inet") | .local' 2>/dev/null
}

# has_addr DEV CIDR — return 0 if CIDR (e.g. 192.0.2.1/24) is on DEV.
has_addr() {
  local dev="$1" addr="${2%%/*}" plen="${2##*/}"
  ip -j addr show dev "$dev" 2>/dev/null | jq -e \
    --arg a "$addr" --argjson p "$plen" \
    '.[0].addr_info[] | select(.family=="inet" and .local==$a and .prefixlen==$p)' \
    >/dev/null 2>&1
}

# route_get_src DST — source IP the kernel would pick for DST, or "".
route_get_src() {
  ip -j route get "$1" 2>/dev/null | jq -r '.[0].prefsrc // ""' 2>/dev/null
}

# route_get_dev DST — egress interface the kernel would use for DST, or "".
route_get_dev() {
  ip -j route get "$1" 2>/dev/null | jq -r '.[0].dev // ""' 2>/dev/null
}

# has_route PREFIX — return 0 if PREFIX is in the main routing table.
has_route() {
  ip -j route show "$1" 2>/dev/null | jq -e 'length > 0' >/dev/null 2>&1
}

# route_proto PREFIX — proto field of the first match for PREFIX, or "".
route_proto() {
  ip -j route show "$1" 2>/dev/null | jq -r '.[0].protocol // ""' 2>/dev/null
}

# neigh_state IP — state of IP in the neighbor table ("REACHABLE", "PERMANENT", etc.), or "".
neigh_state() {
  ip -j neigh show dev eth0 2>/dev/null \
    | jq -r --arg ip "$1" '.[] | select(.dst==$ip) | .state[0] // ""' 2>/dev/null \
    | head -n1
}

# nft_rule_count — total number of rules in the current nftables ruleset.
nft_rule_count() {
  nft -j list ruleset 2>/dev/null \
    | jq '[.nftables[] | select(.rule)] | length' 2>/dev/null || echo 0
}

# nft_table_exists FAMILY NAME — return 0 if the table exists.
nft_table_exists() {
  nft -j list tables 2>/dev/null \
    | jq -e --arg f "$1" --arg n "$2" \
      '.nftables[] | select(.table) | .table | select(.family==$f and .name==$n)' \
      >/dev/null 2>&1
}

# nft_counter_packets PATTERN — sum of packet counters for rules matching PATTERN
# (matched against the full `nft list ruleset` text output).
nft_counter_packets() {
  local pattern="$1"
  nft list ruleset 2>/dev/null \
    | grep -E "$pattern" \
    | grep -oE 'packets ([0-9]+)' \
    | awk '{s+=$2} END{print s+0}'
}

# ---------------------------------------------------------------------------
# Active probes
# ---------------------------------------------------------------------------

# ping_ok DST [count] — return 0 if at least one reply came back.
ping_ok() {
  local dst="$1" count="${2:-3}"
  ping -c "$count" -W 1 -n "$dst" >/dev/null 2>&1
}

# ping_unreachable DST — return 0 if the kernel says "Network is unreachable"
# (i.e. no matching route, not a timeout). This proves the route is missing,
# not merely that the host is down.
ping_unreachable() {
  ping -c 1 -W 1 "$1" 2>&1 | grep -q 'Network is unreachable'
}

# tcpdump_bg IFACE OUTFILE [secs] [extra_flags] — start a bounded passive ICMP
# capture. Returns immediately; sets _LAST_TCPDUMP_PID.
_LAST_TCPDUMP_PID=""
tcpdump_bg() {
  local iface="$1" out="$2" secs="${3:-6}" extra="${4:-}"
  # shellcheck disable=SC2086
  timeout "$secs" tcpdump -l -nn $extra -c 50 -i "$iface" 'icmp' \
    >"$out" 2>/dev/null &
  _LAST_TCPDUMP_PID=$!
  _BG_PIDS+=("$_LAST_TCPDUMP_PID")
}

# tcpdump_icmp_count OUTFILE — count ICMP echo request/reply lines.
tcpdump_icmp_count() {
  grep -cE 'ICMP echo (request|reply)' "$1" 2>/dev/null || echo 0
}

# ss_listening_port PORT — return 0 if something is listening on TCP PORT.
ss_listening_port() {
  ss -ltn "sport = :$1" 2>/dev/null | grep -q ":$1"
}
