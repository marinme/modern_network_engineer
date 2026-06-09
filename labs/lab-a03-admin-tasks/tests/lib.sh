#!/usr/bin/env bash
# lib.sh — shared helpers for Lab A03 verification scripts.
#
# Sourced by per-lab test scripts (test-lab-N-*.sh).
# Read-only against live network namespaces: inspects state with ip/sysctl/nft/
# conntrack/tc/lldpcli, sends ICMP with ping, sniffs passively with tcpdump.
# Never creates, deletes, or reconfigures anything.
#
# Conventions:
#   - `set -uo pipefail` (NOT -e): run every check and report all results.
#   - Each check calls `pass` or `fail`; `finish` exits 0 iff nothing failed.

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
        die "missing required command(s): ${missing[*]} (run this inside the article-03 container)"
    fi
}

# --- Temp dir + cleanup ---

_WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/lab-a03-test.XXXXXX")"
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
# Namespace introspection (read-only)
# =============================================================================

# ns_list — named network namespaces, one per line.
ns_list() {
    ip netns list 2>/dev/null | awk '{print $1}'
}

# ns_forwarding NS — print the namespace's net.ipv4.ip_forward value (0/1).
ns_forwarding() {
    ip netns exec "$1" sysctl -n net.ipv4.ip_forward 2>/dev/null
}

# ns_connected_v4 NS — connected IPv4 subnets in NS, one per line as:
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

# ns_route_nexthop_count NS DST — number of nexthops in the FIB lookup for DST.
ns_route_nexthop_count() {
    local ns="$1" dst="$2"
    ip -j -n "$ns" route get "$dst" 2>/dev/null | \
        jq '.[0].nexthops | length // 1' 2>/dev/null || echo 0
}

# ns_route_metric NS DST — list of metric values for routes to DST (may be multiple).
ns_route_metric() {
    local ns="$1" dst="$2"
    ip -j -n "$ns" route show "$dst" 2>/dev/null | \
        jq -r '.[].metric // "0"' 2>/dev/null
}

# ns_table_exists NS TBL — return 0 if routing table TBL has at least one entry.
ns_table_exists() {
    local ns="$1" tbl="$2"
    [ -n "$(ip -n "$ns" route show table "$tbl" 2>/dev/null)" ]
}

# ns_iface_mtu NS IFACE — MTU of interface IFACE in NS.
ns_iface_mtu() {
    local ns="$1" iface="$2"
    ip -j -n "$ns" link show "$iface" 2>/dev/null | jq -r '.[0].mtu' 2>/dev/null
}

# ns_route_pmtu NS DST — cached PMTU for DST (empty if none cached).
ns_route_pmtu() {
    local ns="$1" dst="$2"
    ip -j -n "$ns" route get "$dst" 2>/dev/null | \
        jq -r '.[0].cache? // [] | .[] | select(.mtu) | .mtu' 2>/dev/null | head -1
}

# ns_sysctl NS KEY — read a sysctl value inside NS.
ns_sysctl() {
    ip netns exec "$1" sysctl -n "$2" 2>/dev/null
}

# ns_neigh_state NS IP — NUD state(s) of the neighbor entry for IP in NS.
ns_neigh_state() {
    local ns="$1" ip="$2"
    ip -j -n "$ns" neigh show "$ip" 2>/dev/null | \
        jq -r '.[].state[]?' 2>/dev/null
}

# ns_neigh_lladdr NS IP — MAC address of the neighbor entry for IP in NS.
ns_neigh_lladdr() {
    local ns="$1" ip="$2"
    ip -j -n "$ns" neigh show "$ip" 2>/dev/null | \
        jq -r '.[0].lladdr // empty' 2>/dev/null
}

# ns_neigh_is_proxy NS IP — return 0 if a proxy entry for IP exists in NS.
ns_neigh_is_proxy() {
    local ns="$1" ip="$2"
    ip -j -n "$ns" neigh show proxy 2>/dev/null | \
        jq -e --arg ip "$ip" '.[] | select(.dst==$ip)' >/dev/null 2>&1
}

# ns_vrf_list NS — list VRF name and table pairs, one per line as "<name> <table>".
ns_vrf_list() {
    local ns="$1"
    ip -j -n "$ns" link show type vrf 2>/dev/null | \
        jq -r '.[] | "\(.ifname) \(.linkinfo.info_data.table)"' 2>/dev/null
}

# ns_vrf_table NS VRF — routing table number for VRF in NS.
ns_vrf_table() {
    local ns="$1" vrf="$2"
    ip -d -j -n "$ns" link show "$vrf" 2>/dev/null | \
        jq -r '.[0].linkinfo.info_data.table // empty' 2>/dev/null
}

# =============================================================================
# NFTables introspection
# =============================================================================

# ns_nft_json NS — full nft ruleset as JSON for NS.
ns_nft_json() {
    ip netns exec "$1" nft -j list ruleset 2>/dev/null
}

# ns_nft_has_rule NS PATTERN — return 0 if 'nft list ruleset' matches PATTERN.
ns_nft_has_rule() {
    local ns="$1" pattern="$2"
    ip netns exec "$ns" nft list ruleset 2>/dev/null | grep -qE "$pattern"
}

# ns_nft_chain_policy NS TABLE FAMILY CHAIN — policy (accept/drop) of a chain.
ns_nft_chain_policy() {
    local ns="$1" table="$2" family="$3" chain="$4"
    ip netns exec "$ns" nft -j list chain "$family" "$table" "$chain" 2>/dev/null | \
        jq -r '.nftables[] | .chain? | select(.name=="'"$chain"'") | .policy // empty' \
        2>/dev/null | head -1
}

# =============================================================================
# Conntrack introspection
# =============================================================================

# ns_conntrack_has NS PATTERN — return 0 if conntrack -L output matches PATTERN.
ns_conntrack_has() {
    local ns="$1" pattern="$2"
    ip netns exec "$ns" conntrack -L 2>/dev/null | grep -qE "$pattern"
}

# ns_conntrack_count NS — number of entries in conntrack table.
ns_conntrack_count() {
    ip netns exec "$1" conntrack -C 2>/dev/null || echo 0
}

# =============================================================================
# Bonding introspection
# =============================================================================

# bond_mode NS BOND — bonding mode string (e.g. "active-backup", "802.3ad").
bond_mode() {
    local ns="$1" bond="$2"
    ip netns exec "$ns" cat /proc/net/bonding/"$bond" 2>/dev/null | \
        grep '^Bonding Mode:' | sed 's/Bonding Mode: //'
}

# bond_active_slave NS BOND — currently active slave interface name.
bond_active_slave() {
    local ns="$1" bond="$2"
    ip netns exec "$ns" cat /proc/net/bonding/"$bond" 2>/dev/null | \
        grep '^Currently Active Slave:' | awk '{print $NF}'
}

# bond_partner_present NS BOND — return 0 if LACP partner MAC is non-zero.
bond_partner_present() {
    local ns="$1" bond="$2" mac
    mac=$(ip netns exec "$ns" cat /proc/net/bonding/"$bond" 2>/dev/null | \
          grep -i 'partner.*mac' | head -1 | awk '{print $NF}')
    [ -n "$mac" ] && [ "$mac" != "00:00:00:00:00:00" ]
}

# =============================================================================
# tc / Traffic-Control introspection
# =============================================================================

# ns_tc_has_mirred NS IFACE DIR — return 0 if iface has a mirred action in DIR.
# DIR is "ingress" or "egress".
ns_tc_has_mirred() {
    local ns="$1" iface="$2" dir="$3"
    ip netns exec "$ns" tc -j filter show dev "$iface" "$dir" 2>/dev/null | \
        jq -e '[.[] | .options.actions[]? | select(.kind=="mirred")] | length > 0' \
        >/dev/null 2>&1
}

# =============================================================================
# DHCP introspection
# =============================================================================

# dnsmasq_lease_in_range LEASEFILE MAC CIDR — return 0 if lease file has an
# entry for MAC whose IP is within CIDR.  CIDR like "10.0.0.0/24".
dnsmasq_lease_in_range() {
    local leasefile="$1" mac="$2" cidr="$3"
    [ -f "$leasefile" ] || return 1
    local net pfx ip a b c d netA netB netC
    net="${cidr%/*}"; pfx="${cidr#*/}"
    IFS=. read -r a b c d <<< "$net"
    # simple /8 /16 /24 check
    while IFS=' ' read -r _ entry_mac entry_ip _rest; do
        [ "${entry_mac,,}" = "${mac,,}" ] || continue
        IFS=. read -r ia ib ic id <<< "$entry_ip"
        case "$pfx" in
            8)  [ "$ia" = "$a" ] && return 0;;
            16) [ "$ia" = "$a" ] && [ "$ib" = "$b" ] && return 0;;
            24) [ "$ia" = "$a" ] && [ "$ib" = "$b" ] && [ "$ic" = "$c" ] && return 0;;
        esac
    done < "$leasefile"
    return 1
}

# iface_has_ip_in_cidr NS IFACE CIDR — return 0 if IFACE in NS has an IP in CIDR.
iface_has_ip_in_cidr() {
    local ns="$1" iface="$2" cidr="$3"
    local net pfx a b c
    net="${cidr%/*}"; pfx="${cidr#*/}"
    IFS=. read -r a b c _ <<< "$net"
    while IFS= read -r addr; do
        local ia ib ic
        IFS=. read -r ia ib ic _ <<< "$addr"
        case "$pfx" in
            8)  [ "$ia" = "$a" ] && return 0;;
            16) [ "$ia" = "$a" ] && [ "$ib" = "$b" ] && return 0;;
            24) [ "$ia" = "$a" ] && [ "$ib" = "$b" ] && [ "$ic" = "$c" ] && return 0;;
        esac
    done < <(ip -j -n "$ns" addr show "$iface" 2>/dev/null | \
             jq -r '.[] | .addr_info[] | select(.family=="inet") | .local' 2>/dev/null)
    return 1
}

# =============================================================================
# Service introspection (chrony, rsyslog, lldp)
# =============================================================================

# chrony_synced NS CHRONYC_OPTS — return 0 if chrony has a selected source.
# NS is a namespace name; pass chronyc options like "-h /run/chrony-ns.sock".
chrony_synced() {
    local ns="$1"; shift
    ip netns exec "$ns" chronyc "$@" sources 2>/dev/null | \
        grep -qE '^\^?\*'
}

# rsyslog_received FILE TOKEN — return 0 if FILE contains TOKEN.
rsyslog_received() {
    local file="$1" token="$2"
    [ -f "$file" ] && grep -qF "$token" "$file"
}

# lldp_neighbor NS SOCKET WANT_IFACE — return 0 if lldpd reports at least one
# neighbor on WANT_IFACE.  SOCKET is the path passed to lldpd -u.
lldp_neighbor() {
    local ns="$1" socket="$2" want_iface="$3"
    lldpcli -u "$socket" show neighbors -f json0 2>/dev/null | \
        jq -e --arg iface "$want_iface" \
        '.lldp.interface[$iface].chassis | length > 0' >/dev/null 2>&1
}

# =============================================================================
# Link counters (for health-sweep / capacity tests)
# =============================================================================

# link_rx_bytes NS IFACE — receive byte counter for IFACE in NS.
link_rx_bytes() {
    ip -j -s -n "$1" link show "$2" 2>/dev/null | \
        jq '.[0].stats64.rx.bytes // .[0].stats.rx.bytes // 0' 2>/dev/null
}

# link_tx_bytes NS IFACE — transmit byte counter for IFACE in NS.
link_tx_bytes() {
    ip -j -s -n "$1" link show "$2" 2>/dev/null | \
        jq '.[0].stats64.tx.bytes // .[0].stats.tx.bytes // 0' 2>/dev/null
}

# =============================================================================
# Active probes (benign — same as ping)
# =============================================================================

# ping_ok SRC_NS DST_IP [count] — return 0 if at least one reply came back.
ping_ok() {
    local ns="$1" dst="$2" count="${3:-3}"
    ip netns exec "$ns" ping -c "$count" -W 2 -n "$dst" >/dev/null 2>&1
}

# ping_loss SRC_NS DST_IP [count] — print integer packet-loss percentage.
ping_loss() {
    local ns="$1" dst="$2" count="${3:-3}"
    ip netns exec "$ns" ping -c "$count" -W 2 -n "$dst" 2>/dev/null \
        | grep -oE '[0-9]+% packet loss' | grep -oE '^[0-9]+' | head -n1
}

# ping_mtu_fail SRC_NS DST_IP SIZE — return 0 if ping with DF bit set and
# SIZE-byte payload fails (expected when SIZE exceeds path MTU).
ping_mtu_fail() {
    local ns="$1" dst="$2" size="$3"
    ! ip netns exec "$ns" ping -M do -c 1 -W 2 -s "$size" -n "$dst" \
        >/dev/null 2>&1
}

# =============================================================================
# Passive capture
# =============================================================================

# tcpdump_start NS IFACE OUTFILE [secs] [extra_filter]
# Start a bounded passive capture in the background.
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

# tcpdump_icmp_count OUTFILE — count ICMP echo request/reply lines.
tcpdump_icmp_count() {
    local n
    n="$(grep -cE 'ICMP echo (request|reply)' "$1" 2>/dev/null)" || n=0
    printf '%s\n' "${n:-0}"
}

# tcpdump_tagged_icmp_count OUTFILE — count 802.1Q-tagged ICMP lines.
tcpdump_tagged_icmp_count() {
    local n
    n="$(grep -cE 'vlan [0-9]+,.*ICMP echo (request|reply)' "$1" 2>/dev/null)" || n=0
    printf '%s\n' "${n:-0}"
}

# tcpdump_first_vlan OUTFILE — VLAN id of the first tagged frame in capture.
tcpdump_first_vlan() {
    grep -oE 'vlan [0-9]+' "$1" 2>/dev/null | head -n1 | grep -oE '[0-9]+'
}

# tcpdump_match_count OUTFILE PATTERN — count lines matching PATTERN.
tcpdump_match_count() {
    local n
    n="$(grep -cE "$2" "$1" 2>/dev/null)" || n=0
    printf '%s\n' "${n:-0}"
}

# =============================================================================
# Bridge / VLAN introspection (carried from A02)
# =============================================================================

# ns_bridges NS — bridge device names in NS, one per line.
ns_bridges() {
    ip -j -n "$1" link show type bridge 2>/dev/null | jq -r '.[].ifname' 2>/dev/null
}

# ns_bridge_ports NS BR — ifnames enslaved to bridge BR in NS, one per line.
ns_bridge_ports() {
    local ns="$1" br="$2"
    ip -j -n "$ns" link show master "$br" 2>/dev/null | jq -r '.[].ifname' 2>/dev/null
}

# ns_vlan_filtering NS BR — return 0 if bridge BR in NS has vlan_filtering=1.
ns_vlan_filtering() {
    local ns="$1" br="$2"
    local val
    val="$(ip -d -j -n "$ns" link show "$br" 2>/dev/null | \
           jq '.[0].linkinfo.info_data.vlan_filtering // 0' 2>/dev/null)"
    [ "$val" = "1" ]
}

# port_vlans NS PORT — VLAN ids configured on bridge PORT in NS.
port_vlans() {
    bridge -j -n "$1" vlan show 2>/dev/null | \
        jq -r --arg p "$2" '.[] | select(.ifname==$p) | .vlans[]?.vlan' 2>/dev/null
}

# fdb_has_mac NS BR MAC — return 0 if MAC is in bridge BR's FDB in NS.
fdb_has_mac() {
    local ns="$1" br="$2" mac="$3"
    bridge -j -n "$ns" fdb show br "$br" 2>/dev/null | \
        jq -e --arg m "$mac" --arg br "$br" \
        '.[] | select(.mac==$m and .ifname!=$br)' >/dev/null 2>&1
}

# ns_iface_mac NS IFACE — MAC address of IFACE in NS.
ns_iface_mac() {
    ip -j -n "$1" link show "$2" 2>/dev/null | jq -r '.[0].address // empty' 2>/dev/null
}

# =============================================================================
# Retry helper (for eventually-consistent assertions: chrony, lldp, etc.)
# =============================================================================

# retry SECS CMD [args...] — poll CMD every 2s up to SECS seconds.
# Returns 0 on first success; 1 if SECS elapsed without success.
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
