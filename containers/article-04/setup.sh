#!/bin/bash
# /lab/setup.sh — Build the r1—r2—r3 routing topology for Lab A04.
#
# Creates three network namespaces and the veth pairs connecting them,
# assigns addresses, enables forwarding, and starts FRR in each namespace
# via the frr@<ns> systemd template units.
#
# Run once at the start of your session:
#   /lab/setup.sh
#
# To tear down:
#   /lab/setup.sh teardown
#   (or just exit the container — --rm cleans everything up)
#
# Topology:
#
#   10.0.0.1/32 (lo)       10.0.0.2/32 (lo)       10.0.0.3/32 (lo)
#   ┌─────────┐            ┌─────────┐            ┌─────────┐
#   │   r1    │──veth r1r2─│   r2    │──veth r2r3─│   r3    │
#   └─────────┘            └─────────┘            └─────────┘
#   10.0.12.1/24       10.0.12.2/24 10.0.23.1/24       10.0.23.2/24
#
# FRR socket paths (via --pathspace):
#   /run/frr/r1/  /run/frr/r2/  /run/frr/r3/
#
# Access FRR for a namespace:
#   /lab/frrvtysh r1    or    ip netns exec r1 vtysh -N r1

set -euo pipefail

teardown() {
    echo "==> Tearing down routing topology..."
    systemctl stop 'frr@r1.service' 'frr@r2.service' 'frr@r3.service' 2>/dev/null || true
    sleep 1
    for ns in r1 r2 r3; do
        ip netns del "$ns" 2>/dev/null || true
    done
    rm -rf /run/frr/r1 /run/frr/r2 /run/frr/r3
    echo "==> Done."
}

if [ "${1:-}" = "teardown" ]; then
    teardown
    exit 0
fi

# Check for existing topology
if ip netns list 2>/dev/null | grep -qE '^r[123]( |$)'; then
    echo "==> Topology already exists. Run '/lab/setup.sh teardown' first to reset."
    ip netns list
    exit 0
fi

echo "==> Building r1—r2—r3 routing topology..."

# ── Namespaces ──────────────────────────────────────────────────────────────
for ns in r1 r2 r3; do
    ip netns add "$ns"
    ip netns exec "$ns" ip link set lo up
done

# ── Veth pairs ──────────────────────────────────────────────────────────────

# r1 ↔ r2
ip link add r1-r2 type veth peer name r2-r1
ip link set r1-r2 netns r1
ip link set r2-r1 netns r2
ip netns exec r1 ip addr add 10.0.12.1/24 dev r1-r2
ip netns exec r2 ip addr add 10.0.12.2/24 dev r2-r1
ip netns exec r1 ip link set r1-r2 up
ip netns exec r2 ip link set r2-r1 up

# r2 ↔ r3
ip link add r2-r3 type veth peer name r3-r2
ip link set r2-r3 netns r2
ip link set r3-r2 netns r3
ip netns exec r2 ip addr add 10.0.23.1/24 dev r2-r3
ip netns exec r3 ip addr add 10.0.23.2/24 dev r3-r2
ip netns exec r2 ip link set r2-r3 up
ip netns exec r3 ip link set r3-r2 up

# ── Loopback addresses ───────────────────────────────────────────────────────
ip netns exec r1 ip addr add 10.0.0.1/32 dev lo
ip netns exec r2 ip addr add 10.0.0.2/32 dev lo
ip netns exec r3 ip addr add 10.0.0.3/32 dev lo

# ── Kernel forwarding ────────────────────────────────────────────────────────
for ns in r1 r2 r3; do
    ip netns exec "$ns" sysctl -qw net.ipv4.ip_forward=1
done

# ── Per-namespace FRR config directories ────────────────────────────────────
for ns in r1 r2 r3; do
    mkdir -p "/etc/frr/$ns"
    # Copy the enabled daemons list; reader can modify per-namespace if needed
    cp /etc/frr/daemons "/etc/frr/$ns/daemons"
    # Empty integrated config — reader fills this in via vtysh
    touch "/etc/frr/$ns/frr.conf"
    # vtysh.conf: tell vtysh to use the pathspace sockets
    echo 'service integrated-vtysh-config' > "/etc/frr/$ns/vtysh.conf"
    chown -R frr:frr "/etc/frr/$ns"
done

# ── Start FRR in each namespace ─────────────────────────────────────────────
echo "==> Starting FRR in r1, r2, r3..."
systemctl start frr@r1.service frr@r2.service frr@r3.service

# Wait for FRR sockets to appear (watchfrr takes a moment)
for ns in r1 r2 r3; do
    printf "  Waiting for frr@%s..." "$ns"
    for _ in $(seq 1 30); do
        if [ -S "/run/frr/$ns/zebra.vty" ] 2>/dev/null; then
            printf " ready\n"
            break
        fi
        sleep 1
        printf "."
    done
    if [ ! -S "/run/frr/$ns/zebra.vty" ] 2>/dev/null; then
        printf " TIMEOUT (check: systemctl status frr@%s)\n" "$ns"
    fi
done

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "==> Routing topology ready:"
ip netns list
echo ""
echo "  Namespaces:  r1  r2  r3"
echo "  r1: 10.0.12.1/24 (r1-r2)  lo: 10.0.0.1/32"
echo "  r2: 10.0.12.2/24 (r2-r1)  10.0.23.1/24 (r2-r3)  lo: 10.0.0.2/32"
echo "  r3: 10.0.23.2/24 (r3-r2)  lo: 10.0.0.3/32"
echo ""
echo "  FRR: frr@r1 frr@r2 frr@r3 (check: systemctl status 'frr@*')"
echo "  Connect: /lab/frrvtysh r1  (or: ip netns exec r1 vtysh -N r1)"
echo ""
echo "  Next: ./tests/routing/test.sh 1   (RIB vs FIB check)"
