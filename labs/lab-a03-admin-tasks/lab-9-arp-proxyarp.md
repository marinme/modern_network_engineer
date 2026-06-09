# Lab A03 — ARP and Proxy ARP

Part of **[Lab A03 — Common Network-Admin Tasks](./README.md)**. Read the README first for the [container setup](./README.md#the-setup), prerequisites, and cleanup conventions.

This lab adds PERMANENT ARP entries (bypassing dynamic ARP) and enables proxy ARP so a router answers ARP on behalf of a host on another subnet. The proxy-ARP scenario lets two hosts on different subnets think they are on the same wire.

```mermaid
graph LR
  h1["h1\n10.0.0.1/24"] -- "" --> r["r\nfwd=1\nproxy_arp on veth-r-h1\nproxy entry for 10.99.0.1"]
  h3["h3\n10.99.0.1/32\n(different subnet)"] -- "" --> r
```

## Part A — PERMANENT (static) ARP entry

```bash
ip netns add h1
ip netns add h2

ip link add veth-h1 type veth peer name veth-h2
ip link set veth-h1 netns h1
ip link set veth-h2 netns h2
ip -n h1 addr add 10.0.0.1/24 dev veth-h1
ip -n h2 addr add 10.0.0.2/24 dev veth-h2
ip -n h1 link set veth-h1 up
ip -n h2 link set veth-h2 up

# Get h2's MAC so we can install it statically on h1
H2_MAC=$(ip -n h2 -j link show veth-h2 | jq -r '.[0].address')
echo "h2 MAC: $H2_MAC"

# Install PERMANENT ARP entry for h2's IP on h1
ip -n h1 neigh add 10.0.0.2 lladdr "$H2_MAC" dev veth-h1 nud permanent
```

Verify:

```bash
ip -n h1 neigh show                  # shows PERMANENT state
ip -j -n h1 neigh show 10.0.0.2 | jq '.[0].state'
ip netns exec h1 ping -c 3 10.0.0.2  # works without ARP (uses the static entry)
```

Watch: with the PERMANENT entry, `tcpdump` on `h1`'s interface will NOT show any ARP requests for `10.0.0.2` — the kernel skips the ARP lookup entirely.

```bash
ip netns exec h1 tcpdump -i veth-h1 -c 10 -n &
ip netns exec h1 ping -c 3 10.0.0.2
wait; kill %1 2>/dev/null || true
# Notice: no ARP lines in the output
```

## Part B — Proxy ARP

`h1` is on `10.0.0.0/24`. `h3` is on `10.99.0.0/24` — a different subnet. Normally `h1` would need a route to reach `h3`. With proxy ARP on `r`, `h1` can ARP for `h3`'s IP directly, get `r`'s MAC back, and send traffic that `r` then forwards.

```bash
ip netns add r
ip netns add h3

# h1 ↔ r  (existing namespaces, but connect r to h1's /24)
ip link add veth-r-h1 type veth peer name veth-h1-r
ip link set veth-r-h1 netns r
ip link set veth-h1-r netns h1
ip -n r  addr add 10.0.0.254/24 dev veth-r-h1
ip -n h1 addr add 10.0.0.1/24   dev veth-h1-r   # h1 on /24 (separate veth from Part A)
ip -n r  link set veth-r-h1 up
ip -n h1 link set veth-h1-r up

# r ↔ h3  (10.99.0.0/24)
ip link add veth-r-h3 type veth peer name veth-h3
ip link set veth-r-h3 netns r
ip link set veth-h3 netns h3
ip -n r  addr add 10.99.0.254/24 dev veth-r-h3
ip -n h3 addr add 10.99.0.1/24   dev veth-h3
ip -n r  link set veth-r-h3 up
ip -n h3 link set veth-h3 up

ip netns exec r sysctl -w net.ipv4.ip_forward=1

# h1 has NO route to 10.99.0.0/24 — it thinks 10.99.0.1 is on its local /24
# (no `ip route add` for h3's network on h1)

# Enable proxy ARP on r's h1-facing interface
ip netns exec r sysctl -w net.ipv4.conf.veth-r-h1.proxy_arp=1

# Add a static proxy entry for h3's IP (more precise than global proxy_arp)
ip -n r neigh add proxy 10.99.0.1 dev veth-r-h1
```

Verify:

```bash
ip netns exec r sysctl net.ipv4.conf.veth-r-h1.proxy_arp   # should be 1
ip -n r neigh show proxy                 # shows the proxy entry for 10.99.0.1

# h1 pings h3 as if it were on the local /24 — r answers the ARP
ip netns exec h1 ping -c 3 10.99.0.1

# After the ping, h1's ARP cache shows 10.99.0.1 → r's MAC (not h3's MAC)
R_MAC=$(ip -n r -j link show veth-r-h1 | jq -r '.[0].address')
echo "r's MAC: $R_MAC"
ip -n h1 neigh show 10.99.0.1   # should show r's MAC for h3's IP
```

## Test your work

```bash
./tests/test.sh 9
```

The test verifies the PERMANENT ARP entry (NUD state = PERMANENT, lladdr present), checks that proxy ARP is enabled on the router interface, confirms the proxy neighbor entry exists, verifies that h1's neighbor cache for h3's IP holds the router's MAC, and checks end-to-end reachability.

## Optional extension

Disable proxy ARP and observe what happens:

```bash
ip netns exec r sysctl -w net.ipv4.conf.veth-r-h1.proxy_arp=0
ip -n h1 neigh flush dev veth-h1-r        # clear h1's ARP cache
ip netns exec h1 ping -c 2 -W 1 10.99.0.1  # should now fail
```

## Comprehension questions

<details>
<summary>Answers (click to expand)</summary>

**1. What happens to the ARP table state for a PERMANENT entry when the interface goes down?**

PERMANENT entries survive interface down/up events — they are static configuration, not dynamic state. They are removed only with `ip neigh del` or `ip neigh flush`. This distinguishes them from `REACHABLE` entries (which expire) and `STALE` entries (which await confirmation but will be refreshed on use).

**2. When would proxy ARP be problematic?**

If `proxy_arp=1` is set globally (not with specific proxy entries), the router answers ARP for *any* destination it can route to. If two hosts on the same subnet happen to share an IP prefix that the router can also reach, the router may intercept ARPs that should be answered by the real host. It can also mislead hosts into thinking all destinations are local, bypassing routing logic. Use static proxy entries (`ip neigh add ... proxy`) for surgical control.

**3. What is the difference between `ip neigh add ... proxy` and `proxy_arp=1`?**

`proxy_arp=1` sysctl makes the kernel answer ARP for any destination reachable via other interfaces — very broad. `ip neigh add 10.99.0.1 proxy dev eth0` installs a specific proxy entry: the kernel only answers ARP for exactly `10.99.0.1` on `eth0`. The specific entry is more predictable in production; the sysctl is simpler for scenarios where you want full proxy-ARP behavior on an interface.

</details>

## Teardown

```bash
for ns in h1 h2 r h3; do ip netns del "$ns" 2>/dev/null; done; true
```

---

Next: **[Lab A03 — MTU and PMTU](./lab-10-mtu-pmtu.md)** demonstrates path MTU discovery and the kernel PMTU cache.
