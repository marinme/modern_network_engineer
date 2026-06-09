# Lab A03 — DHCP Server and Relay

Part of **[Lab A03 — Common Network-Admin Tasks](./README.md)**. Read the README first for the [container setup](./README.md#the-setup), prerequisites, and cleanup conventions.

This lab runs `dnsmasq` as a DHCP server and `dhcrelay` as a relay agent. Part A: a client acquires a lease directly from the server on the same segment. Part B: a client on a *different* subnet gets a lease via a relay, matching the `ip helper-address` pattern from IOS.

```mermaid
graph LR
  subgraph PartA["Part A — Direct"]
    dhcpc["dhcpc (client)\nveth-client"] -- "10.0.0.0/24" --> srv["srv\ndnsmasq\npool 10.0.0.100-200"]
  end
  subgraph PartB["Part B — Relay"]
    remote["remote (client)\nveth-remote\n10.1.0.0/24"] -- "" --> r["r\nfwd=1\ndhcrelay"] -- "" --> srv2["srv\ndnsmasq\npool 10.0.0.x\nand 10.1.0.x"]
  end
```

## Part A — DHCP server (direct)

```bash
ip netns add srv
ip netns add dhcpc

# srv ↔ dhcpc  (10.0.0.0/24)
ip link add veth-srv type veth peer name veth-client
ip link set veth-srv netns srv
ip link set veth-client netns dhcpc

ip -n srv  addr add 10.0.0.1/24 dev veth-srv
ip -n srv  link set veth-srv up
ip -n dhcpc link set veth-client up   # no static IP — dhclient will configure it
```

Start dnsmasq on `srv`:

```bash
ip netns exec srv dnsmasq \
    --interface=veth-srv \
    --bind-interfaces \
    --except-interface=lo \
    --port=0 \
    --no-resolv \
    --dhcp-range=10.0.0.100,10.0.0.200,1h \
    --dhcp-option=3,10.0.0.1 \
    --dhcp-leasefile=/tmp/leases-a.txt \
    --pid-file=/tmp/dnsmasq-a.pid
```

Acquire a lease:

```bash
ip netns exec dhcpc dhclient -v veth-client -lf /tmp/dhclient-a.leases
```

Verify:

```bash
cat /tmp/leases-a.txt                       # epoch  mac  ip  hostname
ip -n dhcpc addr show veth-client           # dhcpc should have an address in 10.0.0.100-200
```

## Part B — DHCP relay

Add a relay namespace and a second subnet:

```bash
ip netns add r
ip netns add remote

# srv ↔ r  (10.0.0.0/24 — server-side)
ip link add veth-r-srv type veth peer name veth-srv2
ip link set veth-r-srv netns r
ip link set veth-srv2 netns srv
ip -n r   addr add 10.0.0.254/24 dev veth-r-srv
ip -n srv addr add 10.0.0.253/24 dev veth-srv2   # second address on srv
ip -n r   link set veth-r-srv up
ip -n srv link set veth-srv2 up

# r ↔ remote  (10.1.0.0/24 — client-side)
ip link add veth-r-remote type veth peer name veth-remote
ip link set veth-r-remote netns r
ip link set veth-remote netns remote
ip -n r      addr add 10.1.0.1/24 dev veth-r-remote
ip -n remote link set veth-remote up
ip -n r      link set veth-r-remote up

ip netns exec r sysctl -w net.ipv4.ip_forward=1
```

Add a pool for the remote subnet to dnsmasq on `srv`:

```bash
# Kill the existing dnsmasq and restart with both pools
kill "$(cat /tmp/dnsmasq-a.pid 2>/dev/null)" 2>/dev/null; sleep 1

ip netns exec srv dnsmasq \
    --interface=veth-srv \
    --interface=veth-srv2 \
    --bind-interfaces \
    --except-interface=lo \
    --port=0 \
    --no-resolv \
    --dhcp-range=10.0.0.100,10.0.0.200,1h \
    --dhcp-range=10.1.0.100,10.1.0.200,1h \
    --dhcp-option=3,10.0.0.1 \
    --dhcp-leasefile=/tmp/leases-b.txt \
    --pid-file=/tmp/dnsmasq-b.pid
```

Start the relay on `r`:

```bash
# dhcrelay -d runs in foreground
ip netns exec r dhcrelay -d -i veth-r-remote -i veth-r-srv 10.0.0.253 &
```

Acquire a lease from the remote subnet:

```bash
ip netns exec remote dhclient -v veth-remote -lf /tmp/dhclient-b.leases
```

Verify:

```bash
cat /tmp/leases-b.txt
# Should show a lease with IP in 10.1.0.100-200 and the client's MAC.
# The subnet (10.1.x) is different from the server's subnet (10.0.x) — proving relay.

ip -n remote addr show veth-remote
```

## Test your work

```bash
./tests/test.sh 7
```

The test finds the dnsmasq lease file(s), reads the client's veth MAC, verifies a lease exists in the configured range, and (for Part B) confirms the leased IP is on the relay subnet (10.1.x), not the server subnet (10.0.x).

## Optional extension

Add a static DHCP assignment so a specific MAC always gets the same IP:

```bash
# In dnsmasq options, add:
# --dhcp-host=<mac>,10.0.0.50,myhost,infinite
# Find the client MAC:
ip -n dhcpc link show veth-client | grep link/ether
# Then kill and restart dnsmasq with --dhcp-host=<mac>,10.0.0.50
```

## Comprehension questions

<details>
<summary>Answers (click to expand)</summary>

**1. What is `giaddr` and why must the relay have an IP on the client's subnet?**

`giaddr` (Gateway IP Address) is a field in the DHCP request that the relay sets to its own IP on the interface where it received the request. The DHCP server uses `giaddr` to determine which subnet pool to allocate from (it matches the `giaddr` against its configured `dhcp-range` subnets). If the relay has no IP on the client-facing interface, `giaddr` is 0.0.0.0 and the server cannot determine the correct pool.

**2. Why use `--port=0` when running dnsmasq as DHCP-only?**

`dnsmasq` defaults to serving DNS on port 53. In a container where another process might be using port 53, or when you only want DHCP without DNS, `--port=0` disables the DNS server entirely. Without it, `dnsmasq` will fail to start if port 53 is already bound.

**3. What option in dnsmasq corresponds to IOS `ip dhcp excluded-addresses`?**

`--dhcp-range` defines the allocatable pool. To exclude addresses, make the range boundaries avoid them. For precise exclusions: use `--dhcp-host=<mac>,<ip>,ignore` to tell dnsmasq to ignore requests from specific hosts, or manually configure the range to not include specific addresses (e.g., start the range at `.100` leaves `.1`–`.99` unmanaged).

</details>

## Teardown

```bash
kill "$(cat /tmp/dnsmasq-a.pid 2>/dev/null)" 2>/dev/null
kill "$(cat /tmp/dnsmasq-b.pid 2>/dev/null)" 2>/dev/null
for ns in srv dhcpc r remote; do ip netns del "$ns" 2>/dev/null; done; true
```

---

Next: **[Lab A03 — VRF and Reverse-Path Filtering](./lab-8-vrf-rpf.md)** builds VRF routing isolation and demonstrates `rp_filter` asymmetric routing drops.
