# Lab A03 — VRF and Reverse-Path Filtering

Part of **[Lab A03 — Common Network-Admin Tasks](./README.md)**. Read the README first for the [container setup](./README.md#the-setup), prerequisites, and cleanup conventions.

This lab builds two VRFs on a single router and verifies routing isolation between them. The second part demonstrates `rp_filter` — strict-mode drops an asymmetrically-routed packet, and `nstat` shows the counter increment.

```mermaid
graph LR
  blue["hblue\n10.0.100.1/24"] -- "" --> r["r\nvrf-blue table 100\nvrf-red  table 200\nfwd=1"]
  red["hred\n10.0.200.1/24"] -- "" --> r
  r -. "cross-VRF\n(should fail)" .-> blue
```

## Part A — VRF isolation

```bash
ip netns add r
ip netns add hblue
ip netns add hred

# r ↔ hblue
ip link add veth-r-blue type veth peer name veth-blue
ip link set veth-r-blue netns r
ip link set veth-blue netns hblue
ip -n hblue addr add 10.0.100.1/24 dev veth-blue
ip -n hblue link set veth-blue up

# r ↔ hred
ip link add veth-r-red type veth peer name veth-red
ip link set veth-r-red netns r
ip link set veth-red netns hred
ip -n hred addr add 10.0.200.1/24 dev veth-red
ip -n hred link set veth-red up

ip netns exec r sysctl -w net.ipv4.ip_forward=1

# Create VRFs on r
ip -n r link add vrf-blue type vrf table 100
ip -n r link set vrf-blue up
ip -n r link add vrf-red  type vrf table 200
ip -n r link set vrf-red  up

# Enslave interfaces to their VRFs (routes follow the interface)
ip -n r link set veth-r-blue master vrf-blue
ip -n r link set veth-r-red  master vrf-red

# Assign addresses AFTER enslaving — they land in the correct VRF table
ip -n r addr add 10.0.100.254/24 dev veth-r-blue
ip -n r addr add 10.0.200.254/24 dev veth-r-red
ip -n r link set veth-r-blue up
ip -n r link set veth-r-red  up

# Host default routes
ip -n hblue route add default via 10.0.100.254
ip -n hred  route add default via 10.0.200.254
```

Verify VRF isolation:

```bash
ip -n r vrf show                          # shows vrf-blue(100) and vrf-red(200)
ip -n r route show vrf vrf-blue           # 10.0.100.0/24 only
ip -n r route show vrf vrf-red            # 10.0.200.0/24 only

ip netns exec hblue ping -c 3 10.0.100.254   # in-VRF: should succeed
ip netns exec hred  ping -c 3 10.0.200.254   # in-VRF: should succeed

# Cross-VRF should fail (no route leaked between tables)
ip netns exec hblue ping -c 2 -W 1 10.0.200.1  # should fail
ip netns exec hred  ping -c 2 -W 1 10.0.100.1  # should fail
```

Run a command in VRF context from `r`:

```bash
ip netns exec r ip vrf exec vrf-blue ping -c 3 10.0.100.1
```

## Part B — Reverse-path filtering

Create an asymmetric routing scenario: a host sends traffic on one interface but `r` would return via a different interface, triggering strict rp_filter.

```bash
ip netns add hasymc
ip netns add r2    # acts as the "wrong return path" router

# hasymc ↔ r  (path A — incoming)
ip link add veth-r-a type veth peer name veth-a
ip link set veth-r-a netns r; ip link set veth-a netns hasymc
ip -n r      addr add 192.168.1.1/30 dev veth-r-a
ip -n hasymc addr add 192.168.1.2/30 dev veth-a
ip -n r      link set veth-r-a up; ip -n hasymc link set veth-a up

# hasymc ↔ r  (path B — alternative return path)
ip link add veth-r-b type veth peer name veth-b
ip link set veth-r-b netns r; ip link set veth-b netns hasymc
ip -n r      addr add 192.168.2.1/30 dev veth-r-b
ip -n hasymc addr add 192.168.2.2/30 dev veth-b
ip -n r      link set veth-r-b up; ip -n hasymc link set veth-b up

# hasymc sends traffic from 192.168.1.2 on veth-a (arrives at veth-r-a on r)
# but r's route back to 192.168.1.2 goes via the 192.168.1.0 connected route —
# wait, that IS via veth-r-a, so asymmetry needs to be from a source that enters
# on one interface but whose return path is the OTHER interface.

# Make it asymmetric: hasymc sends SRC=192.168.2.2 packets via veth-a (not its natural path)
# The packet arrives on veth-r-a, but r's route to 192.168.2.2 is via veth-r-b.
# With strict rp_filter on veth-r-a, r drops it.

# Set up rp_filter on r's incoming interface
ip netns exec r sysctl -w net.ipv4.conf.all.rp_filter=1
ip netns exec r sysctl -w net.ipv4.conf.veth-r-a.rp_filter=1

# Record nstat baseline
ip netns exec r nstat -az 2>/dev/null | grep -i 'rpf\|InNoRoute\|reverse' > /tmp/rpf-before.txt

# Generate an asymmetric packet: hasymc pings from 192.168.2.2, but routes it via veth-a
ip -n hasymc route add 192.168.1.1/32 via 192.168.1.1 dev veth-a   # force path A
ip netns exec hasymc ping -c 2 -W 1 -I veth-a 192.168.1.1 || true  # should be dropped

# Check for rp_filter drops
ip netns exec r nstat -az 2>/dev/null | grep -i 'rpf\|InNoRoute'
```

Compare with loose mode:

```bash
ip netns exec r sysctl -w net.ipv4.conf.all.rp_filter=2
ip netns exec r sysctl -w net.ipv4.conf.veth-r-a.rp_filter=2
ip netns exec hasymc ping -c 2 -W 1 -I 192.168.2.2 192.168.1.1 || true
```

## Test your work

```bash
./tests/test.sh 8
```

The test verifies the VRF interfaces exist with their table numbers, checks in-VRF reachability, confirms cross-VRF isolation, and reads the `rp_filter` sysctl values.

## Optional extension

Route leaking between VRFs: install a static route in one VRF that explicitly leaks a prefix from the other:

```bash
ip -n r route add 10.0.200.0/24 vrf vrf-blue nexthop via 10.0.200.254
```

Now `hblue` can reach `hred` but the route appears only in the blue VRF table.

## Comprehension questions

<details>
<summary>Answers (click to expand)</summary>

**1. What happens to an interface's existing routes when it is enslaved to a VRF?**

All routes derived from the interface's address (connected routes) move to the VRF's routing table immediately. Any static routes that used the interface as the outgoing interface also move to the VRF table. This is why you should add addresses *after* enslaving — otherwise the routes land in the main table and need to be manually moved.

**2. What is `ip vrf exec` and when would you use it?**

`ip vrf exec vrf-name command` runs a command (e.g., `ping`, `curl`) in the context of a VRF — the process uses the VRF's routing table for all lookups. This is analogous to adding `vrf vrf-name` to a command in IOS or running a command inside a VRF shell. It is essential for testing connectivity within a VRF without leaving the current shell.

**3. Why is `net.ipv4.conf.all.rp_filter` significant?**

The effective `rp_filter` for an interface is `max(all.rp_filter, <iface>.rp_filter)`. Setting only the interface value is overridden by `all` if `all` is higher. Always set both `all` and the specific interface to get the intended behavior. The `all` knob acts as a floor/ceiling that can unexpectedly override per-interface settings.

</details>

## Teardown

```bash
for ns in r hblue hred hasymc; do ip netns del "$ns" 2>/dev/null; done; true
```

---

Next: **[Lab A03 — ARP and Proxy ARP](./lab-9-arp-proxyarp.md)** adds PERMANENT neighbor entries and enables proxy ARP for off-subnet hosts.
