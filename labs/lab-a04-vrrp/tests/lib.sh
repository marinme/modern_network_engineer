#!/usr/bin/env bash
# lib.sh — shared helpers for Lab A04 verification scripts.
#
# Sourced by per-lab test scripts (test-lab-N-*.sh).
# Read-only against live network namespaces and the FRR daemons:
# inspects state with ip/sysctl/vtysh/journalctl, sends ICMP with ping,
# sniffs passively with tcpdump.  Never creates, deletes, or reconfigures.
#
# Conventions:
#   - `set -uo pipefail` (NOT -e): run every check and report all results.
#   - Each check calls `pass` or `fail`; `finish` exits 0 iff nothing failed.
#
# FRR socket paths:  /run/frr/<ns>/  (--pathspace <ns>)
# vtysh access:      ip netns exec <ns> vtysh -N <ns> -c '<cmd>'
# Wrapper:           /lab/frrvtysh <ns> -c '<cmd>'

set -uo pipefail

# --- Colour support ---
if [ -t 1 ]; then
    _C_GREEN=$'\033[32m'; _C_RED=$'\033[31m'; _C_YEL=$'\033[33m'
    _C_BLU=$'\033[34m';   _C_RST=$'\033[0m'
else
    _C_GREEN=''; _C_RED=''; _C_YEL=''; _C_BLU=''; _C_RST=''
fi

_FAILS=0

pass()    { printf '%s[PASS]%s %s\n' "$_C_GREEN" "$_C_RST" "$*"; }
fail()    { printf '%s[FAIL]%s %s\n' "$_C_RED"   "$_C_RST" "$*"; (( _FAILS++ )) || true; }
info()    { printf '%s[INFO]%s %s\n' "$_C_BLU"   "$_C_RST" "$*"; }
section() { printf '\n%s=== %s ===%s\n' "$_C_YEL" "$*" "$_C_RST"; }
die()     { printf '%s[ERROR]%s %s\n' "$_C_RED" "$_C_RST" "$*" >&2; exit 2; }
finish()  { [ "$_FAILS" -eq 0 ] && exit 0 || exit 1; }

# --- Preflight ---

require_cmds() {
    local missing=() c
    for c in "$@"; do
        command -v "$c" >/dev/null 2>&1 || missing+=("$c")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        die "missing required command(s): ${missing[*]} (run this inside the article-04 container)"
    fi
}

# --- Temp dir + cleanup ---

_WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/lab-a04-test.XXXXXX")"
_BG_PIDS=()

_cleanup() {
    local p
    for p in "${_BG_PIDS[@]:-}"; do
        [ -n "$p" ] && kill "$p" 2>/dev/null || true
    done
    rm -rf "$_WORKDIR" 2>/dev/null || true
}
trap _cleanup EXIT INT TERM

# =============================================================================
# Namespace introspection (read-only, carried from A03)
# =============================================================================

# ns_list — named network namespaces, one per line.
ns_list() {
    ip netns list 2>/dev/null | awk '{print $1}'
}

# ns_forwarding NS — net.ipv4.ip_forward value in NS (0/1).
ns_forwarding() {
    ip netns exec "$1" sysctl -n net.ipv4.ip_forward 2>/dev/null
}

# ns_sysctl NS KEY — read a sysctl value inside NS.
ns_sysctl() {
    ip netns exec "$1" sysctl -n "$2" 2>/dev/null
}

# ns_connected_v4 NS — connected IPv4 subnets, one per line as:
#   "<subnet> <dev> <ip>"
ns_connected_v4() {
    local ns="$1"
    ip -j -n "$ns" addr show 2>/dev/null | jq -r '
        .[] | .ifname as $dev |
        .addr_info[] |
        select(.family=="inet" and .scope=="global") |
        "\(.local | split(".") | .[0:3] | join(".")).0/\(.prefixlen)  \($dev)  \(.local)"
    ' 2>/dev/null | sort -u
}

# ns_iface_kind NS IFACE — link type (e.g. "veth", "bridge", "vlan").
ns_iface_kind() {
    ip -d -j -n "$1" link show "$2" 2>/dev/null | \
        jq -r '.[0].linkinfo.info_kind // "unknown"' 2>/dev/null
}

# ns_route_nexthop_count NS DST — number of nexthops for DST in NS.
ns_route_nexthop_count() {
    local ns="$1" dst="$2"
    ip -j -n "$ns" route get "$dst" 2>/dev/null | \
        jq '.[0].nexthops | length // 1' 2>/dev/null || echo 0
}

# =============================================================================
# Active probes
# =============================================================================

# ping_ok SRC_NS DST_IP [count] — return 0 if at least one reply came back.
ping_ok() {
    local ns="$1" dst="$2" count="${3:-3}"
    ip netns exec "$ns" ping -c "$count" -W 2 -n "$dst" >/dev/null 2>&1
}

# =============================================================================
# Passive capture
# =============================================================================

_LAST_TCPDUMP_PID=""
tcpdump_start() {
    local ns="$1" iface="$2" out="$3" secs="${4:-6}" extra="${5:-}"
    # shellcheck disable=SC2086
    ip netns exec "$ns" timeout "$secs" \
        tcpdump -i "$iface" -nn -l $extra \
        > "$out" 2>/dev/null &
    _LAST_TCPDUMP_PID=$!
    _BG_PIDS+=("$_LAST_TCPDUMP_PID")
}

# tcpdump_match_count OUTFILE PATTERN — count lines matching PATTERN.
tcpdump_match_count() {
    local n
    n="$(grep -cE "$2" "$1" 2>/dev/null)" || n=0
    printf '%s\n' "${n:-0}"
}

# =============================================================================
# Retry helper
# =============================================================================

# retry SECS CMD [args...] — poll CMD every 2s up to SECS seconds.
retry() {
    local secs="$1"; shift
    local elapsed=0
    while [ "$elapsed" -lt "$secs" ]; do
        "$@" && return 0
        sleep 2
        elapsed=$(( elapsed + 2 ))
    done
    return 1
}

# =============================================================================
# FRR daemon introspection (read-only)
# All functions run vtysh commands inside the specified namespace.
# FRR sockets are at /run/frr/<ns>/ via --pathspace <ns>.
# =============================================================================

# _vtysh_json NS CMD — run 'show ... json' in NS and return JSON; exit 2 on error.
_vtysh_json() {
    local ns="$1" cmd="$2"
    ip netns exec "$ns" vtysh -N "$ns" -c "$cmd" 2>/dev/null
}

# frr_daemon_running NS DAEMON — return 0 if DAEMON process is up in NS.
# DAEMON is e.g. "zebra", "bgpd", "ospfd".
frr_daemon_running() {
    local ns="$1" daemon="$2"
    ip netns exec "$ns" pgrep -x "$daemon" >/dev/null 2>&1
}

# frr_socket_ready NS — return 0 if the FRR zebra vty socket exists (FRR up).
frr_socket_ready() {
    local ns="$1"
    [ -S "/run/frr/$ns/zebra.vty" ] 2>/dev/null
}

# frr_ospf_neighbor_state NS NEIGHBOR_ID — OSPF state string for a specific neighbor.
# Returns e.g. "Full" or "" if not found.
frr_ospf_neighbor_state() {
    local ns="$1" nbr_id="$2"
    _vtysh_json "$ns" "show ip ospf neighbor $nbr_id json" 2>/dev/null | \
        jq -r '.default? // . | .neighbors? // . |
               to_entries[0].value[0]? // to_entries[0].value? |
               .nbrState? // .state? // empty' 2>/dev/null | head -1
}

# frr_ospf_any_full NS — return 0 if any OSPF neighbor is in Full state.
frr_ospf_any_full() {
    local ns="$1"
    _vtysh_json "$ns" "show ip ospf neighbor json" 2>/dev/null | \
        jq -e '
            .default? // . |
            .neighbors? // . |
            to_entries[] |
            .value[] |
            select((.nbrState? // .state? // "") | test("Full"; "i"))
        ' >/dev/null 2>&1
}

# frr_ospf_neighbor_count NS — number of OSPF neighbors in any state.
frr_ospf_neighbor_count() {
    local ns="$1"
    _vtysh_json "$ns" "show ip ospf neighbor json" 2>/dev/null | \
        jq '
            .default? // . |
            .neighbors? // . |
            [to_entries[] | .value[]] | length
        ' 2>/dev/null || echo 0
}

# frr_bgp_peer_state NS PEER — BGP session state for PEER (IP or interface name).
# Returns e.g. "Established", "Idle", "Active".
frr_bgp_peer_state() {
    local ns="$1" peer="$2"
    _vtysh_json "$ns" "show ip bgp summary json" 2>/dev/null | \
        jq -r --arg p "$peer" '
            .ipv4Unicast? // . |
            .peers? // {} |
            (.[$p]? // to_entries[] | .value | select(.desc? == $p or .idType? == "interface")) |
            .state? // "Unknown"
        ' 2>/dev/null | head -1
}

# frr_bgp_any_established NS — return 0 if any BGP peer is Established.
frr_bgp_any_established() {
    local ns="$1"
    _vtysh_json "$ns" "show ip bgp summary json" 2>/dev/null | \
        jq -e '
            .ipv4Unicast? // . |
            .peers? // {} |
            to_entries[] |
            .value |
            select(.state? == "Established")
        ' >/dev/null 2>&1
}

# frr_bgp_peer_established NS PEER — return 0 if PEER is Established.
frr_bgp_peer_established() {
    local ns="$1" peer="$2"
    _vtysh_json "$ns" "show ip bgp summary json" 2>/dev/null | \
        jq -e --arg p "$peer" '
            .ipv4Unicast? // . |
            .peers? // {} |
            to_entries[] | .value |
            select((.peerIp? == $p or .desc? == $p) and .state? == "Established")
        ' >/dev/null 2>&1
}

# frr_bgp_prefix_in_fib NS PREFIX PROTO — return 0 if PREFIX is in the kernel
# FIB in NS with the given proto (e.g. "bgp", "ospf").
frr_bgp_prefix_in_fib() {
    local ns="$1" prefix="$2" proto="${3:-bgp}"
    ip -n "$ns" route show proto "$proto" 2>/dev/null | grep -qF "$prefix"
}

# frr_bgp_unnumbered_session NS IFACE — return 0 if there is an Established BGP
# session on an interface-based (unnumbered) peer for IFACE.
frr_bgp_unnumbered_session() {
    local ns="$1" iface="$2"
    _vtysh_json "$ns" "show ip bgp summary json" 2>/dev/null | \
        jq -e --arg iface "$iface" '
            .ipv4Unicast? // . |
            .peers? // {} |
            to_entries[] | .value |
            select(.idType? == "interface" and (.peerIp? | test($iface; "i"))
                   and .state? == "Established")
        ' >/dev/null 2>&1
}

# frr_bgp_peer_is_link_local NS PEER — return 0 if PEER's next-hop in the
# BGP table is an IPv6 link-local address (fe80::...).
frr_bgp_peer_link_local_nexthop() {
    local ns="$1"
    _vtysh_json "$ns" "show ip bgp json" 2>/dev/null | \
        jq -e '
            .routes? // {} |
            to_entries[] | .value[] |
            .nexthops[]? |
            select(.ip? | test("^fe80:"; "i"))
        ' >/dev/null 2>&1
}

# frr_bfd_peer_up NS — return 0 if any BFD peer is Up.
frr_bfd_peer_up() {
    local ns="$1"
    _vtysh_json "$ns" "show bfd peers json" 2>/dev/null | \
        jq -e '.[].status? == "up"' >/dev/null 2>&1
}

# frr_bfd_interval_ms NS — smallest configured TX interval in ms across all peers.
frr_bfd_interval_ms() {
    local ns="$1"
    _vtysh_json "$ns" "show bfd peers json" 2>/dev/null | \
        jq '[.[].txInterval? // 300] | min' 2>/dev/null || echo 300
}

# frr_bfd_peer_count NS — number of BFD peers in any state.
frr_bfd_peer_count() {
    local ns="$1"
    _vtysh_json "$ns" "show bfd peers json" 2>/dev/null | \
        jq 'length' 2>/dev/null || echo 0
}

# frr_config_file_exists NS — return 0 if /etc/frr/<ns>/frr.conf is non-empty.
frr_config_file_exists() {
    local ns="$1"
    [ -s "/etc/frr/$ns/frr.conf" ] 2>/dev/null
}

# frr_config_has_router NS PROTO — return 0 if frr.conf contains "router <proto>".
frr_config_has_router() {
    local ns="$1" proto="$2"
    grep -qE "^router $proto" "/etc/frr/$ns/frr.conf" 2>/dev/null
}

# frr_vrrp_state NS IFACE VR_ID — VRRP state for virtual-router VR_ID on IFACE.
# Returns "Master", "Backup", or "" if not found.
frr_vrrp_state() {
    local ns="$1" iface="$2" vr_id="$3"
    _vtysh_json "$ns" "show vrrp json" 2>/dev/null | \
        jq -r --arg iface "$iface" --arg vrid "$vr_id" '
            to_entries[] |
            select(.key | test($iface; "i")) |
            .value | to_entries[] |
            select(.key == $vrid) |
            .value.state? // empty
        ' 2>/dev/null | head -1
}

# frr_pim_iface_enabled NS IFACE — return 0 if PIM is enabled on IFACE in NS.
frr_pim_iface_enabled() {
    local ns="$1" iface="$2"
    _vtysh_json "$ns" "show ip pim interface json" 2>/dev/null | \
        jq -e --arg iface "$iface" '.[$iface]? | .pimEnabled? == true' \
        >/dev/null 2>&1
}

# frr_igmp_group_joined NS GROUP — return 0 if GROUP is in the IGMP table in NS.
frr_igmp_group_joined() {
    local ns="$1" group="$2"
    _vtysh_json "$ns" "show ip igmp groups json" 2>/dev/null | \
        jq -e --arg g "$group" '
            .. | strings | test($g; "i")
        ' >/dev/null 2>&1
}

# frr_mroute_sg_exists NS SRC GROUP — return 0 if (S,G) entry exists in FRR mroute.
frr_mroute_sg_exists() {
    local ns="$1" src="$2" grp="$3"
    _vtysh_json "$ns" "show ip mroute json" 2>/dev/null | \
        jq -e --arg sg "($src, $grp)" '.. | strings | test($sg; "i")' \
        >/dev/null 2>&1 || \
    _vtysh_json "$ns" "show ip mroute" 2>/dev/null | \
        grep -qE "\($src, $grp\)"
}

# ip_mroute_has NS SRC GROUP — return 0 if kernel mroute table has (S,G) entry.
ip_mroute_has() {
    local ns="$1" src="$2" grp="$3"
    ip netns exec "$ns" ip mroute show 2>/dev/null | \
        grep -qE "\($src, $grp\)"
}

# ip_maddr_has NS IFACE GROUP — return 0 if GROUP is in kernel maddr table on IFACE.
ip_maddr_has() {
    local ns="$1" iface="$2" grp="$3"
    ip -n "$ns" maddr show dev "$iface" 2>/dev/null | \
        grep -qiF "$grp"
}

# vip_on_iface NS IFACE VIP — return 0 if VIP (no prefix) is assigned to IFACE in NS.
vip_on_iface() {
    local ns="$1" iface="$2" vip="$3"
    ip -j -n "$ns" addr show dev "$iface" 2>/dev/null | \
        jq -e --arg vip "$vip" '
            .[] | .addr_info[] | select(.family=="inet" and .local==$vip)
        ' >/dev/null 2>&1
}

# =============================================================================
# Journal introspection (read-only)
# =============================================================================

# journal_unit_has_entries UNIT — return 0 if unit has any journal entries.
journal_unit_has_entries() {
    local unit="$1"
    journalctl -u "$unit" -n 1 --no-pager -q 2>/dev/null | grep -q .
}

# journal_kernel_has_entries — return 0 if kernel has any journal entries.
journal_kernel_has_entries() {
    journalctl -k -n 1 --no-pager -q 2>/dev/null | grep -q .
}

# journal_frr_namespaces_present NAMESPACES... — return 0 if all listed frr@<ns>
# units have journal entries.
journal_frr_namespaces_present() {
    local ok=true
    for ns in "$@"; do
        journal_unit_has_entries "frr@${ns}.service" || ok=false
    done
    [ "$ok" = "true" ]
}

# journal_json_query_works — return 0 if journalctl -o json-pretty produces
# parseable JSON output.
journal_json_query_works() {
    journalctl -n 5 -o json-pretty --no-pager 2>/dev/null | \
        jq -e '.__REALTIME_TIMESTAMP != null' >/dev/null 2>&1
}
