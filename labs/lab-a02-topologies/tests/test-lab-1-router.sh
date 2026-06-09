#!/usr/bin/env bash
# test-lab-1-router.sh — verify a built Lab 1 (host — router — host) topology.
#
# VERIFY-ONLY and NON-DESTRUCTIVE. Run it *after* you build Lab 1 inside the
# article-02 workbench. It does not create, delete, or reconfigure anything:
# it discovers the namespace names and IP addresses you actually used, then
# checks the lab's objective —
#
#   1. the middle namespace forwards (net.ipv4.ip_forward = 1),
#   2. each host routes to the other via that router,
#   3. one host can ping the other end to end,
#   4. and the traffic genuinely transits the router (tcpdump on BOTH legs),
#      so a same-subnet shortcut can't sneak a pass.
#
# Exit status: 0 if every check passed, 1 if any failed, 2 on setup error.
#
# Usage (inside the container, after building the lab):
#     ./tests/test-lab-1-router.sh

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"

require_cmds ip jq tcpdump ping timeout awk grep

# ---------------------------------------------------------------------------
# Discover the host — router — host triple from the live namespaces
# ---------------------------------------------------------------------------
section "Discovering topology"

mapfile -t NAMESPACES < <(ns_list)
if [ "${#NAMESPACES[@]}" -lt 3 ]; then
  fail "expected at least 3 namespaces (two hosts + a router); found ${#NAMESPACES[@]}: ${NAMESPACES[*]:-none}"
  finish
fi
info "namespaces present: ${NAMESPACES[*]}"

# first IPv4 address NS owns inside SUBNET (empty if none)
host_ip_in_subnet() {
  ns_connected_v4 "$1" | awk -v s="$2" '$1==s {print $3; exit}'
}

ROUTER=""
HOSTA_NS=""; HOSTA_IP=""; HOSTA_LEGDEV=""; HOSTA_GW=""
HOSTB_NS=""; HOSTB_IP=""; HOSTB_LEGDEV=""; HOSTB_GW=""

declare -a f_dev f_subnet f_gw f_hostns f_hostip
for cand in "${NAMESPACES[@]}"; do
  [ "$(ns_forwarding "$cand")" = "1" ] || continue          # routers forward

  mapfile -t legs < <(ns_connected_v4 "$cand")
  [ "${#legs[@]}" -ge 2 ] || continue                       # ...and have >=2 subnets

  f_dev=(); f_subnet=(); f_gw=(); f_hostns=(); f_hostip=()
  for leg in "${legs[@]}"; do
    read -r lsub ldev lgw <<<"$leg"
    for h in "${NAMESPACES[@]}"; do
      [ "$h" = "$cand" ] && continue
      hip="$(host_ip_in_subnet "$h" "$lsub")"
      [ -n "$hip" ] || continue
      f_dev+=("$ldev"); f_subnet+=("$lsub"); f_gw+=("$lgw")
      f_hostns+=("$h"); f_hostip+=("$hip")
      break
    done
  done

  if [ "${#f_hostns[@]}" -ge 2 ]; then
    ROUTER="$cand"
    HOSTA_NS="${f_hostns[0]}"; HOSTA_IP="${f_hostip[0]}"; HOSTA_LEGDEV="${f_dev[0]}"; HOSTA_GW="${f_gw[0]}"
    HOSTB_NS="${f_hostns[1]}"; HOSTB_IP="${f_hostip[1]}"; HOSTB_LEGDEV="${f_dev[1]}"; HOSTB_GW="${f_gw[1]}"
    break
  fi
done

if [ -z "$ROUTER" ]; then
  fail "could not identify a forwarding router with two host-bearing subnets"
  info "expected one namespace with net.ipv4.ip_forward=1 and two connected IPv4 subnets, each holding another namespace (a host). What I see:"
  for ns in "${NAMESPACES[@]}"; do
    info "  $ns: ip_forward=$(ns_forwarding "$ns") subnets=[$(ns_connected_v4 "$ns" | awk '{print $1}' | paste -sd, -)]"
  done
  finish
fi

pass "detected router '$ROUTER' (ip_forward=1) joining two subnets"
info "  leg A: $HOSTA_LEGDEV gw $HOSTA_GW  ->  host '$HOSTA_NS' ($HOSTA_IP)"
info "  leg B: $HOSTB_LEGDEV gw $HOSTB_GW  ->  host '$HOSTB_NS' ($HOSTB_IP)"

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------
section "Checks"

# 1. forwarding on the router
if [ "$(ns_forwarding "$ROUTER")" = "1" ]; then
  pass "router '$ROUTER' has net.ipv4.ip_forward = 1"
else
  fail "router '$ROUTER' net.ipv4.ip_forward is not 1 (it won't forward)"
fi

# 2. each host's route to the other resolves via the router (the static-route mechanism)
check_host_route() {
  local from_ns="$1" to_ip="$2" want_gw="$3"
  read -r gw dev <<<"$(ns_route_nexthop "$from_ns" "$to_ip")"
  if [ "$gw" = "$want_gw" ]; then
    pass "host '$from_ns' routes to $to_ip via the router ($gw on $dev)"
  else
    fail "host '$from_ns' should reach $to_ip via the router ($want_gw); resolver says gateway=$gw dev=$dev"
  fi
}
check_host_route "$HOSTA_NS" "$HOSTB_IP" "$HOSTA_GW"
check_host_route "$HOSTB_NS" "$HOSTA_IP" "$HOSTB_GW"

# 3. end-to-end reachability
ping_out="$(ip netns exec "$HOSTA_NS" ping -c 3 -W 1 -n "$HOSTB_IP" 2>&1)"
ping_rc=$?
loss="$(printf '%s\n' "$ping_out" | grep -oE '[0-9]+% packet loss' | grep -oE '^[0-9]+' | head -n1)"
if [ "$ping_rc" -eq 0 ]; then
  pass "reachability: '$HOSTA_NS' pings $HOSTB_IP through the router (${loss:-0}% loss)"
else
  fail "reachability: '$HOSTA_NS' cannot ping $HOSTB_IP (${loss:-100}% loss)"
fi

# ---------------------------------------------------------------------------
# Mechanism: the traffic must cross the router, proven on BOTH legs
# ---------------------------------------------------------------------------
section "Mechanism: traffic must transit the router"

capA="$_WORKDIR/legA.txt"; capB="$_WORKDIR/legB.txt"
tcpdump_start "$ROUTER" "$HOSTA_LEGDEV" "$capA" 8; pidA="$_LAST_TCPDUMP_PID"
tcpdump_start "$ROUTER" "$HOSTB_LEGDEV" "$capB" 8; pidB="$_LAST_TCPDUMP_PID"
sleep 1                                                   # let the captures attach
ip netns exec "$HOSTA_NS" ping -c 3 -W 1 -n "$HOSTB_IP" >/dev/null 2>&1
sleep 1                                                   # let the last reply land
kill "$pidA" "$pidB" 2>/dev/null || true
wait "$pidA" "$pidB" 2>/dev/null || true

nA="$(tcpdump_icmp_count "$capA")"
nB="$(tcpdump_icmp_count "$capB")"
if [ "$nA" -ge 1 ] && [ "$nB" -ge 1 ]; then
  pass "ICMP seen on both router legs ($HOSTA_LEGDEV=$nA, $HOSTB_LEGDEV=$nB) — traffic transits '$ROUTER'"
else
  fail "ICMP not seen on both legs ($HOSTA_LEGDEV=$nA, $HOSTB_LEGDEV=$nB) — traffic did not cross the router as expected"
fi

finish
