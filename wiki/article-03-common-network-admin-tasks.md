---
type: topic
tags: [article, foundation, linux, common-tasks, ai-callback]
article_number: 3
cluster: Foundation
created: 2026-06-03
updated: 2026-06-09
sources: [[[network-engineer-modernization-series]]]
status: draft
---

# Common Network-Admin Tasks, Done in Base Linux

[[article-01-linux-for-network-engineers|Article 1]] gave you the translation table and the `ip` suite. [[article-02-interfaces-namespaces-topologies|Article 2]] gave you the primitive: network namespaces, interface types, and the four-move idiom. This article is the bookmark-bar article. It is the one you will open in a second tab when you are mid-task on a Linux box and need to remember how to configure NAT, set up a VLAN trunk, or run a DHCP server without reaching for a vendor appliance.

Twenty-one recurring tasks. Each one follows the same template. By the end, nearly everything you would normally do on a router or switch in the first month on a new network has a Linux equivalent in your muscle memory. This isn't to say that a linux box will be replacing your hardware devices, but instead to allow you to understand how it likely works internally on the underlying linux platform and to give you a much cheaper means of setting up a lab to learn a new technology.

This article assumes you have read Articles 1 and 2 and that you already understand the *why* behind each task — what NAT does, why VLANs segment broadcast domains, what a DHCP relay is for. The article teaches Linux implementation, not networking concepts. It also assumes that you have a base understanding of linux systems (like managing services, generically; or, installing packages; or, navigating the file system)

## Routing and failover

### Inspect the routing table

We covered this in the first article, but are repeating here for reference completeness. On a router, `show ip route` shows the RIB; `show ip cef` shows the FIB. On Linux, `ip route show` reads the kernel routing table directly — there is no separate RIB/FIB distinction visible at this level.

```bash
ip route show                    # everything
ip route show default            # just the default route
ip route show table 100          # a specific routing table (VRF territory)
ip route show proto static       # only routes installed by `ip route add`
ip route get 8.8.8.8             # which path a specific destination would take
ip -j route show | jq '.'        # machine-parseable
```

The `proto` field on each route tells you who installed it: `kernel` (from an address being assigned), `static` (from `ip route add`), `dhcp` (from a DHCP client), or a routing daemon name like `ospf` or `bgp` when FRR is running.

`ip route get 8.8.8.8` is the Linux equivalent of `show ip route 8.8.8.8` — it runs the kernel's FIB lookup and prints the nexthop, interface, and source address that a real packet would use. It is your first stop when debugging "why is this packet not going where I expect."

**Watch out for:** there is no `show ip route summary` equivalent. `ip route show | wc -l` approximates it; `ip route show table all` reveals routes across every routing table, including policy-routing tables you may not have known existed.

### Static routes with failover

A single static route: `ip route add 10.0.0.0/24 via 10.1.0.1`. An ECMP (equal-cost multipath) route and a metric-based backup are two distinct patterns.

**Metric-based primary/backup** (one is preferred, the other activates on failure):

```bash
ip route add default via 10.0.0.1 metric 100   # primary
ip route add default via 10.0.0.2 metric 200   # backup (higher metric = lower preference)
```

When 10.0.0.1 is up both routes exist but only the lower-metric one is used. When the primary goes away (or you `ip route del` it), the backup takes over.

**ECMP — load-sharing across two equal-cost nexthops:**

```bash
# Noting here the \ for ignoring newlines but gives us readability
ip route add default \
    nexthop via 10.0.0.1 weight 1 \
    nexthop via 10.0.0.2 weight 1
```

Verify:

```bash
ip route show default            # shows either one route or two with metrics
ip -j route get 8.8.8.8 | jq '.[0].nexthops // .[0].gateway'
```

**Watch out for:** ECMP on Linux is per-flow by default (same 5-tuple always takes the same path), not per-packet. Weight controls the ratio of flows, not an exact byte ratio. Two routes to the same prefix with different metrics are *not* ECMP — they are primary/backup. ECMP uses a single route entry with a `nexthops` array.

## Access control

### Configure a stateful ACL

Article 1 introduced `nftables` for recognition. Here is enough to use it.

`nftables` has three levels: **table** (a namespace for chains), **chain** (where rules live, attached to a hook), and **rule** (a match + verdict). At first, you might think this is similar to the Cisco MQC setup with policy-maps, class-maps, and service-policies. I did, but it didn't pan out. There are similarities between those structures, but the functionality is spread around differently and its hard to find a direct translation between them. I tried a few times with Claude to make one and it just became a convoluted mess. The best way to handle learning this concept for me is just to read, then do, then repeat.

The `inet` family covers both IPv4 and IPv6 in one ruleset. Two hooks matter for ACL work: **input** (traffic destined *for the box itself*) and **forward** (traffic the box is *routing through*). A ruleset with only a `forward` chain leaves the router's own IP unprotected — management-plane traffic (SSH to the router, OSPF hellos arriving on the box) bypasses it entirely. A complete ACL needs both.

**Forward chain** — restrict what flows *through* the router:

```bash
nft add table inet filter
nft add chain inet filter forward \
    '{ type filter hook forward priority 0; policy drop; }'
nft add rule inet filter forward ct state established,related accept
nft add rule inet filter forward \
    ip saddr 10.0.0.0/8 tcp dport 22 accept
```

**Input chain** — restrict what reaches *the router itself*:

```bash
nft add chain inet filter input \
    '{ type filter hook input priority 0; policy drop; }'
nft add rule inet filter input iif lo accept
nft add rule inet filter input ct state established,related accept
nft add rule inet filter input ip saddr 10.0.0.0/8 tcp dport 22 accept
nft add rule inet filter input ip protocol icmp accept
```

The `ct state established,related` rule accepts return traffic for connections that were already permitted. The `policy drop` on the chain is what makes this stateful-drop rather than stateless-permit-unless-denied. The `iif lo` rule on the input chain is mandatory — without it, loopback traffic (used by local services communicating with themselves) is dropped and the box misbehaves in subtle ways.

**Named sets** — when the same list of prefixes or ports appears in multiple rules, define it once:

```bash
nft add set inet filter trusted-nets \
    '{ type ipv4_addr; flags interval; }'
nft add element inet filter trusted-nets { 10.0.0.0/8, 192.168.0.0/16 }

nft add rule inet filter forward \
    ip saddr @trusted-nets tcp dport 22 accept
nft add rule inet filter input \
    ip saddr @trusted-nets tcp dport { 22, 443, 8080 } accept
```

The `@trusted-nets` notation references the set by name. Adding an element to the set immediately affects every rule that references it — no rule reload required. Sets of type `ipv4_addr` with `flags interval` support CIDR prefixes; without the flag, only host addresses are valid.

**Logging** — add a log rule before the implicit policy drop so you can see what is being rejected:

```bash
nft add rule inet filter forward \
    limit rate 10/minute log prefix "nft-fwd-drop: " drop
```

The `limit rate 10/minute` prevents log flooding under a port scan. Without rate limiting, a single scan fills the kernel ring buffer and chokes syslog. Logged lines appear in `dmesg` and are forwarded to the system journal: `journalctl -k -g "nft-fwd-drop"`.

**Counters** — rules do not count packets by default. Add the `counter` keyword to measure traffic on a specific rule:

```bash
nft add rule inet filter forward \
    ip saddr 10.0.0.0/8 tcp dport 22 counter accept
nft list ruleset           # shows packets/bytes inline with the rule
```

This is the `show ip access-list` equivalent. Counters reset on ruleset flush; use named counters (`nft add counter inet filter ssh-hits`) if you need them to survive rule changes independently.

**Saving and loading** — `nft add` commands are ephemeral; they live in kernel state and vanish on reboot. Persist with:

```bash
nft list ruleset > /etc/nftables.conf    # dump current state to a file
nft -f /etc/nftables.conf               # reload from file
```

The file format is a block syntax that mirrors the nft-command output:

```
flush table inet filter
table inet filter {
    chain forward {
        type filter hook forward priority 0; policy drop;
        ct state established,related accept
        ip saddr 10.0.0.0/8 tcp dport 22 accept
    }
    chain input {
        type filter hook input priority 0; policy drop;
        iif lo accept
        ct state established,related accept
        ip protocol icmp accept
    }
}
```

`nft -f` applies the file as a single atomic transaction — all rules are replaced at once. Unlike `iptables-restore`, which processes rules line by line and can leave the firewall in a partially-updated state, nftables commits the entire new ruleset or rolls back the entire thing on error.

Verify:

```bash
nft list ruleset                            # everything
nft list chain inet filter forward         # just this chain
nft list set inet filter trusted-nets      # set members
nft -j list ruleset | jq '.'               # JSON for scripting
```

**Watch out for:** the `policy` is on the **chain**, not the table. A table without any chains drops nothing. The `inet` family is not the same as running separate `ip` and `ip6` tables — it is a single unified ruleset, so one rule covers both protocol families. `ct state` auto-loads the `nf_conntrack` module on first use; if conntrack is disabled at the kernel level, this rule fails silently and connection tracking does not happen. When reloading with `nft -f`, begin the file with `flush table inet filter` — without it, rules accumulate on top of the existing ones rather than replacing them. Priority `0` for filter chains is the convention; NAT chains use `-100` for prerouting and `100` for postrouting — these correspond to specific netfilter hook priorities, not arbitrary ordering numbers.
### Capture traffic between two specific hosts

On IOS: `monitor capture MYCAP interface GigabitEthernet0/0 match ip any any`. On Linux, `tcpdump` takes a [BPF filter](https://biot.com/capstats/bpf.html) expression:

```bash
tcpdump -i eth0 'host 10.0.0.1 and host 10.0.0.2'
tcpdump -i eth0 'host 10.0.0.1 and host 10.0.0.2 and tcp'
tcpdump -i any  'host 10.0.0.1 and host 10.0.0.2'    # all interfaces
tcpdump -i eth0 -w /tmp/capture.pcap                  # write to file
tcpdump -r /tmp/capture.pcap -n                       # read it back
```

If the hosts are not on the same interface as your capture point (you are not in-path), use a mirror (Lab 6) to copy the frames to a dummy interface and capture there.

**Watch out for:** `-i any` works but captures with a `Linux cooked` header instead of Ethernet, which changes the DLT type. Wireshark handles it; some tools do not. Use `-i any` for quick checks; use a specific interface for pcap files you will hand to someone else.

## VLANs and trunking

### Set up an 802.1Q VLAN trunk

This was covered in the previous article, but put here for reference. On IOS: `interface GigabitEthernet0/0.100`, `encapsulation dot1Q 100`. On Linux: a VLAN-aware bridge.

```bash
# Create a VLAN-aware bridge
ip link add br0 type bridge
ip link set br0 type bridge vlan_filtering 1
ip link set br0 up

# Access port: eth0 carries VLAN 10 untagged (pvid = ingress VLAN for untagged frames)
ip link set eth0 master br0
bridge vlan add vid 10 dev eth0 pvid untagged
bridge vlan del vid 1 dev eth0          # remove the default VLAN 1

# Trunk port: eth1 carries VLANs 10 and 20 tagged
ip link set eth1 master br0
bridge vlan add vid 10 dev eth1
bridge vlan add vid 20 dev eth1
bridge vlan del vid 1 dev eth1
```

Verify:

```bash
bridge vlan show                        # which VLANs on which ports, pvid, untagged flags
bridge fdb show br br0                  # MAC table
ip -d link show br0                     # shows vlan_filtering 1
```

**Watch out for:** every bridge port defaults to `pvid 1` (VLAN 1, untagged) when enslaved. You must explicitly delete VLAN 1 and configure the right VIDs. `pvid` means "untagged ingress traffic on this port gets this VLAN ID." To give the bridge itself an IP on a VLAN (an SVI equivalent), use: `ip link add link br0 name br0.10 type vlan id 10`.

## Link aggregation (bonding)

### Bond two interfaces

On IOS: `interface Port-channel1`, `channel-group 1 mode active`. On Linux, `bonding` is a kernel module that creates a logical interface. Some linux versions do not include the module for bonding by default and if this does not work on some flavor you are using, then you should do some research on how to add it. Some useful docs on the arguments of iproute2 based bonds are [here](https://oneuptime.com/blog/post/2026-03-20-create-bond-ip-link-add-bond/view) since the ip link man docs don't contain that information. For your reference here as well, miimon is media independent interface monitoring, otherwise known as a heartbeat interval on the local interfaces rather than a carrier detect mechanism that is the default. From some cursory reading on the subject, I find that miimon is required in the 802.3ad (LACP) specification for detecting health of member interfaces, but that for single interfaces carrier detect offloads this to the NIC driver instead. 

```bash
# active-backup (HA — one active, one standby)
ip link add bond0 type bond
ip link set bond0 type bond mode active-backup miimon 100
ip link set eth0 down && ip link set eth0 master bond0
ip link set eth1 down && ip link set eth1 master bond0
ip link set bond0 up

# 802.3ad LACP (both links active, requires a LACP partner on the other end)
ip link add bond0 type bond
ip link set bond0 type bond mode 802.3ad miimon 100 lacp_rate fast
ip link set eth0 down && ip link set eth0 master bond0
ip link set eth1 down && ip link set eth1 master bond0
ip link set bond0 up
```

Verify:

```bash
cat /proc/net/bonding/bond0        # mode, active slave, LACP partner info
ip -d link show bond0              # bond parameters inline
cat /sys/class/net/bond0/bonding/active_slave   # current active member
```

**Watch out for:** member interfaces must be DOWN before enslaving — `ip link set eth0 master bond0` silently fails or corrupts state if eth0 is up. For 802.3ad, the far end must *also* be a bond (or a switch with LACP enabled); a plain interface will not negotiate LACP. `miimon 100` checks interface liveness every 100 ms; it detects link-down but not traffic loss through a live cable. `arp_interval` / `arp_ip_target` adds ARP-based liveness checking, which catches silent far-end failures.

## NAT and port forwarding

### Configure NAT/PAT outbound

On IOS: `ip nat inside source list ACL interface GigabitEthernet0/0 overload`. On Linux: an `nft` masquerade rule in the nat table.

```bash
nft add table ip nat
nft add chain ip nat postrouting \
    '{ type nat hook postrouting priority 100; }'
nft add rule ip nat postrouting oifname "eth0" masquerade
```

Then enable forwarding in the router namespace:

```bash
sysctl -w net.ipv4.ip_forward=1
```

Verify:

```bash
nft list table ip nat
conntrack -L                       # shows SNAT tuples for active flows
conntrack -S                       # counters
```

**Watch out for:** use the `ip` family (not `inet`) for NAT — IPv6 NAT uses `ip6` and almost no one does it. `masquerade` differs from `snat` in that masquerade looks up the current egress IP at packet time, making it correct even on DHCP interfaces where the IP changes. `conntrack -L` shows nothing until the first packet flows through — prime it with a ping or curl from a host behind NAT.

### Port-forward (DNAT) for a service

On IOS: `ip nat inside source static tcp <inside-ip> 80 <outside-ip> 8080`. On Linux, add a `prerouting` chain with a DNAT rule:

```bash
nft add chain ip nat prerouting \
    '{ type nat hook prerouting priority -100; }'
nft add rule ip nat prerouting \
    iif "eth0" tcp dport 8080 dnat to 10.0.0.5:80
```

Verify from the WAN side:

```bash
nft list table ip nat              # shows both pre and postrouting chains
conntrack -L | grep dnat           # DNAT tuple once a connection arrives
ss -tlnp                           # listener on 10.0.0.5:80
```

**Watch out for:** the DNAT target IP must be reachable from the router — if it is on an internal subnet, routing must be correct. The response from 10.0.0.5 must go *back through the router* (not directly to the WAN client), or conntrack cannot de-NAT it — this means default routes on internal hosts must point at the router. For the case where both client and server are behind the same interface ("hairpin NAT"), add a masquerade rule in postrouting for internal-to-internal traffic.

## Port mirroring / SPAN

### Mirror a port

On IOS: `monitor session 1 source interface GigabitEthernet0/0 both` + `destination interface GigabitEthernet0/1`. On Linux, `tc` (Traffic Control) with the `mirred` action:

```bash
# Create a monitor interface (dummy — packets arrive but go nowhere)
ip link add mon0 type dummy
ip link set mon0 up

# Attach a classifier-action qdisc to the interface you want to mirror
tc qdisc add dev eth0 clsact

# Mirror ingress (incoming) traffic to mon0
tc filter add dev eth0 ingress matchall \
    action mirred egress mirror dev mon0

# Also mirror egress (outgoing) traffic
tc filter add dev eth0 egress matchall \
    action mirred egress mirror dev mon0
```

Sniff on the monitor interface:

```bash
tcpdump -i mon0 -n
```

Verify:

```bash
tc -s qdisc show dev eth0          # shows clsact qdisc + packet counts
tc -s filter show dev eth0 ingress # filter with match counters
```

**Watch out for:** `clsact` is a qdisc (queuing discipline) that lives alongside any existing egress qdisc — it does not replace `pfifo_fast`. The `act_mirred` kernel module must be loaded (`modprobe act_mirred`). The mirror is a copy: the original packet still flows normally. Unlike IOS SPAN, there is no "RSPAN over VLAN" by default, though the `vlan` action can add encapsulation.

## DHCP server and relay

### Run a DHCP server

On IOS: `ip dhcp pool CORP` with `network`, `default-router`, and `dns-server` sub-commands. On Linux, `dnsmasq` in DHCP-only mode is the shortest path:

```bash
dnsmasq \
    --interface=eth0 \
    --bind-interfaces \
    --except-interface=lo \
    --port=0 \
    --no-resolv \
    --dhcp-range=10.0.0.100,10.0.0.200,24h \
    --dhcp-option=3,10.0.0.1 \
    --dhcp-option=6,8.8.8.8 \
    --dhcp-leasefile=/tmp/dnsmasq.leases
```

On the client, acquire a lease: `dhclient eth1` or `dhclient -v eth1` for verbose output.

Verify:

```bash
cat /tmp/dnsmasq.leases            # epoch  mac  ip  hostname  clientid
ip addr show eth1                  # client's interface has an address in range
```

**Watch out for:** `--port=0` disables DNS so dnsmasq does not try to bind port 53 (which a system resolver may already hold). `--bind-interfaces` prevents binding 0.0.0.0:67, which matters when running multiple dnsmasq instances in different namespaces. Always pass `--except-interface=lo` or dnsmasq will try to serve DHCP to itself. Pass `--dhcp-leasefile` so you (and the tests) know where to find leases.

### Run a DHCP relay

On IOS: `ip helper-address 10.0.0.254` under the SVI. On Linux, `dhcrelay` from the `isc-dhcp-relay` package:

```bash
dhcrelay -d -i eth0 -i eth1 10.0.0.254
```

where `eth0` faces the clients and `eth1` faces the DHCP server at `10.0.0.254`. `-d` runs in foreground (useful in a namespace where there is no systemd to manage it).

For the relay to work: the router running `dhcrelay` must have `ip_forward=1` and must have an IP address on the client-facing interface — that IP becomes the `giaddr` (gateway IP address) in the relayed DHCP request, which tells the DHCP server which subnet to allocate from.

Verify:

```bash
cat /tmp/dnsmasq.leases            # a lease for a client on the remote subnet
# The client's subnet in the lease will be different from the server's subnet,
# proving the request was relayed rather than served on-link.
```

**Watch out for:** the DHCP server must have a pool for the client's subnet (identified by the `giaddr`). If the relay is running in a namespace, dnsmasq must be configured with a `dhcp-range` that matches the client's network, not the server's network. `dhcrelay` logs to syslog by default; with `-d` it goes to stdout.

## VRFs and routing isolation

### Set up a VRF

On IOS: `vrf definition MGMT` + `interface GigabitEthernet0/0` → `vrf forwarding MGMT`. On Linux, a VRF is a lightweight kernel object that binds a set of interfaces to a routing table:

```bash
ip link add vrf-mgmt type vrf table 100
ip link set vrf-mgmt up
ip link set eth0 master vrf-mgmt
```

When `eth0` is enslaved, all routes derived from addresses on `eth0` move to table 100. New routes for the VRF: `ip route add 10.0.0.0/8 via 10.0.0.1 vrf vrf-mgmt`.

Verify:

```bash
ip vrf show                        # lists VRFs and their table IDs
ip -d link show type vrf           # shows table number per VRF device
ip route show vrf vrf-mgmt         # routes in this VRF's table
ip vrf exec vrf-mgmt ping 10.0.0.1 # run a command in VRF context
```

**Watch out for:** enslaving an interface to a VRF is disruptive — existing connections on that interface are broken because their routes move to the VRF table. There is no cross-VRF routing without explicit policy routes or route leaking. `ip vrf exec` is the VRF equivalent of `ip netns exec` for running commands in the VRF's routing context.

### Reverse-path filtering

On IOS: `ip verify unicast source reachable-via rx` (strict) or `any` (loose). On Linux, `rp_filter` is a per-interface sysctl with three values:

- `0` — no check (off)
- `1` — strict: the source must be reachable via the *same* interface the packet arrived on
- `2` — loose: the source must be reachable via *any* interface

```bash
# Set both the "all" umbrella and the specific interface.
# The effective value is the maximum of all.X and <iface>.X.
sysctl -w net.ipv4.conf.all.rp_filter=1
sysctl -w net.ipv4.conf.eth0.rp_filter=1
```

Verify:

```bash
sysctl net.ipv4.conf.eth0.rp_filter
nstat -az | grep -i rpfilter       # IPExtInNoRoutes / IpExtInNoRoutes increments on drop
```

**Watch out for:** `all.rp_filter` acts as a maximum — if `all=1` and `eth0=0`, the effective value for `eth0` is still `1`. Asymmetric routing (common with ECMP or policy routing) causes strict-mode (`1`) drops. Loose (`2`) is usually the right default on a multi-homed host; strict is correct when you know traffic is symmetric and want to catch spoofing. `rp_filter` is per-namespace: each namespace's interfaces carry their own value.

## ARP management and proxy ARP

### Static ARP entries

On IOS: `arp 10.0.0.5 0011.2233.4455 arpa`. On Linux:

```bash
ip neigh add 10.0.0.5 lladdr 00:11:22:33:44:55 dev eth0 nud permanent
```

Modify or replace: `ip neigh change 10.0.0.5 lladdr 00:11:22:33:44:66 dev eth0 nud permanent`. Remove: `ip neigh del 10.0.0.5 dev eth0`.

Verify:

```bash
ip neigh show                        # all entries with NUD state
ip -j neigh show dev eth0 | jq '.'   # JSON for scripting
```

**Watch out for:** `nud permanent` = Neighbor Unreachability Detection state of "permanent" — it never ages out and never probes. Other states are `stale` (used but awaiting confirmation), `reachable` (confirmed working within the last N seconds), `delay`, `probe`, and `failed`. A PERMANENT entry bypasses ARP entirely for that IP.

### Proxy ARP

On IOS: `ip proxy-arp` under an interface. On Linux, it is a per-interface sysctl plus optional static proxy entries:

```bash
# Enable proxy ARP: r will answer ARP for any destination it can route to
sysctl -w net.ipv4.conf.eth0.proxy_arp=1

# Optional: answer ARP for a *specific* host only (more surgical)
ip neigh add 10.99.0.1 proxy dev eth0
```

When proxy ARP is on, a host on `eth0`'s subnet that ARPs for `10.99.0.1` (which lives elsewhere) will get `r`'s MAC address back, then send packets to `r`, which routes them onward.

Verify:

```bash
sysctl net.ipv4.conf.eth0.proxy_arp
ip neigh show proxy                   # static proxy entries
# On the requesting host, after a ping attempt:
ip neigh show                         # 10.99.0.1 → r's MAC (not 10.99.0.1's own MAC)
```

**Watch out for:** `proxy_arp=1` answers for *all* routable destinations, not just specific ones. This is intentionally broad on a router but can confuse hosts into sending traffic the wrong way. Use static proxy entries (`ip neigh add ... proxy`) for targeted proxy ARP. Both `ip_forward` and `proxy_arp` must be on for proxy ARP to do anything useful — if forwarding is off, r answers the ARP but drops the packet.

## MTU and PMTU discovery

### Set per-interface MTU

On IOS: `ip mtu 1400` under the interface. On Linux:

```bash
ip link set eth0 mtu 1400
```

Verify: `ip link show eth0` — the MTU is in the output on the first line.

**Watch out for:** setting the MTU on one end of a veth pair does not change the other end — each side has its own MTU. On a physical NIC, the driver may round to the nearest supported value (usually a multiple of 4).

### Troubleshoot path MTU

`ping -M do` sets the DF (Don't Fragment) bit. Use it to probe PMTU manually:

```bash
ping -M do -s 1450 10.99.0.1     # DF set, 1450-byte payload (+ 28 headers = 1478 total)
# If path MTU is 1400: "ping: local error: message too long, mtu=1400"

ping -M do -s 1372 10.99.0.1     # 1372 + 28 = 1400 — fits; should succeed
```

After a failed probe, the kernel caches the PMTU in the route cache:

```bash
ip route get 10.99.0.1            # shows "cache  expires Xs mtu 1400"
ip route show cache               # all cached PMTUs
ip route flush cache              # clear the cache to re-probe
```

Verify the mechanism: after running the failing `-s 1450` probe, the kernel received an ICMP Fragmentation Needed message from the bottleneck router and updated its PMTU cache. `ip route get` showing `mtu 1400` proves the ICMP was received and honored.

**Watch out for:** if an intermediate router filters ICMP type 3 code 4 (Fragmentation Needed), PMTU discovery fails silently — TCP connections hang or are very slow, UDP works only with small payloads. This is the "black-hole router" problem. `tcp_mtu_probing=1` in sysctl makes TCP try smaller MSS sizes even without ICMP feedback.

## NTP, syslog, and LLDP

### Configure NTP with chrony

On IOS: `ntp server 10.0.0.1`. On Linux, add a server line to `/etc/chrony.conf`:

```
server 10.0.0.1 iburst
makestep 1.0 3
```

Then signal chrony to reload or start it: `chronyd -f /etc/chrony.conf -d` for foreground with debug. For a lab NTP server with no upstream: add `local stratum 10` to the server's config to make it serve time from its own clock.

Verify:

```bash
chronyc sources           # * = selected source, + = usable, ? = unreachable
chronyc tracking          # Reference ID, stratum, estimated offset
```

**Watch out for:** `iburst` sends 4 packets immediately at startup for faster initial synchronization. Without `makestep`, chrony will slew (gradually adjust) rather than step the clock — which is correct for production but means the first sync after a big offset takes minutes. Two `chronyd` instances in the same container need separate config files and pidfile/socket options (`-f /tmp/server-chrony.conf`).

### Syslog forwarding

On IOS: `logging 10.0.0.5; logging facility local0`. On Linux, add to `/etc/rsyslog.conf`:

```
# TCP forwarding (@@) — reliable, requires imtcp on the collector
*.* @@10.0.0.5:514

# UDP forwarding (@) — fire and forget
*.* @10.0.0.5:514
```

Restart rsyslog or start it: `rsyslogd -f /etc/rsyslog.conf -i /tmp/rsyslog.pid`. Log a test message: `logger -t myapp "test message"`.

On the collector (TCP mode), the rsyslog config must load the TCP input module:

```
module(load="imtcp")
input(type="imtcp" port="514")
*.* /var/log/syslog-remote.log
```

Or use `socat` as a simple TCP collector: `socat -u TCP-LISTEN:514,reuseaddr,fork OPEN:/tmp/collect.log,creat,append`.

Verify: on the collector, check the log file for the token string from `logger`.

**Watch out for:** `@@` (double `@`) is TCP; `@` (single) is UDP. TCP requires the collector to have an `imtcp` input loaded and bound to the port. A `queue.type="LinkedList"` on the forwarding action buffers messages if the collector is unreachable, but the buffer lives in memory and is lost on restart without persistence settings.

### LLDP neighbor discovery

On IOS: `lldp run` globally + `show lldp neighbors detail`. On Linux, `lldpd` is the daemon:

```bash
lldpd -d                        # daemon mode, default socket /run/lldpd.socket
lldpcli show neighbors          # text format
lldpcli -f json show neighbors  # JSON, machine-parseable
```

For multiple `lldpd` instances in one container (one per namespace), each needs its own socket:

```bash
ip netns exec dev lldpd -u /run/lldpd-dev.socket
ip netns exec col lldpd -u /run/lldpd-col.socket
lldpcli -u /run/lldpd-dev.socket show neighbors
```

Verify:

```bash
lldpcli show neighbors detail   # chassis ID, port ID, system description, TTL
```

**Watch out for:** LLDP is Layer 2 — it requires a shared L2 segment (direct veth, or a bridge). LLDP advertises on a ~30-second interval by default; run `lldpcli update` after both daemons are running to trigger an immediate advertisement. `lldpd` needs a `_lldpd` user (created by the package install) and may try to chroot; in a container, run with `-x` to disable chroot if it causes permission errors.

## Quick health sweep and capacity

### Quick health sweep

These five commands give you a full picture of a Linux box's network health in under ten seconds:

```bash
ip -s -s link                    # per-interface: RX/TX bytes, errors, drops, overruns
ss -s                            # socket summary: TCP/UDP state counts
conntrack -S                     # conntrack table stats: max size, current count
conntrack -L 2>/dev/null | head  # sample of active tracked flows
nstat -az | grep -v ' 0 0'       # kernel MIB counters — only non-zero rows
```

`ip -s -s link` is `show interfaces` — it shows the same counters (input errors, output drops) that you look at after a traffic event. `nstat -az` exposes counters like `TcpInErrs`, `IpExtInNoRoutes` (RPF drops), `TcpExtTCPSynRetrans` — things that don't appear in `ip -s` but matter for diagnosing TCP issues.

### Capacity quick-look

To measure real throughput, `iperf3` is the standard:

```bash
# Server side (in the destination namespace or host)
iperf3 -s

# Client side
iperf3 -c 10.99.0.1 -t 5        # 5-second TCP test
iperf3 -c 10.99.0.1 -u -b 100M  # UDP at 100 Mbps
```

For a live bandwidth view, `bmon`, `iftop`, and `nload` are interactive tools worth knowing. They are observation-only — not scriptable — but useful when you want to *watch* traffic in real time.

For scripted rate estimates:

```bash
ethtool -S eth0                  # NIC-level counters: rx_bytes, tx_dropped, etc.
watch -n1 'ip -s link show eth0' # manual rate approximation
```

**Watch out for:** veth interfaces do not have the hardware counters that `ethtool -S` shows on a real NIC — the output is minimal or absent. On physical hosts, `ethtool -S` is where you find queue-level drops (`rx_queue_0_drops`) that `ip -s link` does not surface.

## The Linux appliance: putting it all together

Here is what the previous tasks look like when assembled into a single working box. This is the compounding example — the point at which "I learned a bunch of Linux commands" becomes "I replaced a small vendor appliance."

The topology: three namespaces, `wan`, `r`, and `lan`. `r` is the appliance. It forwards, masquerades outbound traffic, port-forwards a service, enforces an ACL, and serves DHCP to `lan` clients.

```bash
# --- topology ---
ip netns add wan; ip netns add r; ip netns add lan

# wan — r link (172.16.0.0/30)
ip link add veth-r-wan type veth peer name veth-wan
ip link set veth-r-wan netns r; ip link set veth-wan netns wan
ip -n r addr add 172.16.0.2/30 dev veth-r-wan
ip -n wan addr add 172.16.0.1/30 dev veth-wan
ip -n r link set veth-r-wan up; ip -n wan link set veth-wan up

# r — lan link (10.0.0.0/24)
ip link add veth-r-lan type veth peer name veth-lan
ip link set veth-r-lan netns r; ip link set veth-lan netns lan
ip -n r addr add 10.0.0.1/24 dev veth-r-lan
ip -n r link set veth-r-lan up; ip -n lan link set veth-lan up

# --- forwarding and default route ---
ip netns exec r sysctl -w net.ipv4.ip_forward=1
ip -n wan route add default via 172.16.0.2  # wan's "internet" goes through r
ip -n r route add default via 172.16.0.1    # r's default out to wan

# --- NAT: masquerade lan→wan ---
ip netns exec r nft add table ip nat
ip netns exec r nft add chain ip nat postrouting \
    '{ type nat hook postrouting priority 100; }'
ip netns exec r nft add rule ip nat postrouting \
    oifname "veth-r-wan" masquerade

# --- DNAT: port-forward tcp/8080 on wan side to lan service ---
ip netns exec r nft add chain ip nat prerouting \
    '{ type nat hook prerouting priority -100; }'
ip netns exec r nft add rule ip nat prerouting \
    iif "veth-r-wan" tcp dport 8080 dnat to 10.0.0.5:80

# --- ACL: allow established return traffic + SSH from wan; drop the rest ---
ip netns exec r nft add table inet filter
ip netns exec r nft add chain inet filter forward \
    '{ type filter hook forward priority 0; policy drop; }'
ip netns exec r nft add rule inet filter forward \
    ct state established,related accept
ip netns exec r nft add rule inet filter forward \
    iif "veth-r-wan" tcp dport 22 accept

# --- DHCP: serve lan from 10.0.0.100–200 ---
ip netns exec r dnsmasq \
    --interface=veth-r-lan --bind-interfaces --except-interface=lo \
    --port=0 --no-resolv \
    --dhcp-range=10.0.0.100,10.0.0.200,1h \
    --dhcp-option=3,10.0.0.1 \
    --dhcp-leasefile=/tmp/r-leases.txt

# lan client acquires address
ip netns exec lan dhclient veth-lan
```

At this point `lan` has an address, can reach the internet through `r` (via NAT), port 8080 on `wan`'s IP forwards to `lan`'s 10.0.0.5:80, and everything except established-return and SSH is dropped inbound.

What you just configured is unremarkable on Linux. The same stack — forwarding, masquerade, DNAT, stateful ACL, DHCP server — that a small branch-office appliance provides is a handful of `ip`, `nft`, and `dnsmasq` commands. The commands are persistent as long as the namespace exists; [[article-05-production-appliance]] covers making them survive a reboot with `systemd-networkd` and `nft -f`.

## The labs

**[Lab A03 — Routing and Failover](../labs/lab-a03-admin-tasks/lab-1-routing-failover.md).** ECMP multipath routes and metric-based primary/backup. `ip route get` proving which path a packet takes.

**[Lab A03 — Stateful ACL and Capture](../labs/lab-a03-admin-tasks/lab-2-acl-stateful.md).** `nft` forward chain with `policy drop`, `ct state established,related`, and TCP port permit. `tcpdump` capturing between specific hosts.

**[Lab A03 — VLAN Trunk](../labs/lab-a03-admin-tasks/lab-3-vlan-trunk.md).** Two VLAN-aware bridges joined by a trunk. `bridge vlan` configuration, `pvid`, same-VLAN reach across the trunk, cross-VLAN isolation.

**[Lab A03 — Bonding](../labs/lab-a03-admin-tasks/lab-4-bonding.md).** Active-backup bond and an 802.3ad LACP bond. `/proc/net/bonding/` confirms mode and partner negotiation.

**[Lab A03 — NAT and Port-Forward](../labs/lab-a03-admin-tasks/lab-5-nat-pat.md).** Masquerade outbound NAT with conntrack verification. DNAT port-forward to an internal service listener.

**[Lab A03 — Port Mirror / SPAN](../labs/lab-a03-admin-tasks/lab-6-mirror-span.md).** `tc clsact` qdisc and `mirred` filter copying frames to a `dummy` monitor interface. `tcpdump` on the monitor while traffic flows on the original path.

**[Lab A03 — DHCP Server and Relay](../labs/lab-a03-admin-tasks/lab-7-dhcp.md).** `dnsmasq` serving a DHCP pool on a directly-connected subnet. `dhcrelay` forwarding requests from a remote subnet.

**[Lab A03 — VRF and Reverse-Path Filtering](../labs/lab-a03-admin-tasks/lab-8-vrf-rpf.md).** Two VRFs with overlapping address space, in-VRF routing, and cross-VRF isolation. `rp_filter` strict-mode drop verified with `nstat` counters.

**[Lab A03 — ARP and Proxy ARP](../labs/lab-a03-admin-tasks/lab-9-arp-proxyarp.md).** PERMANENT neighbor entry bypassing ARP. `proxy_arp` sysctl enabling a router to answer ARP on behalf of a remote host.

**[Lab A03 — MTU and PMTU](../labs/lab-a03-admin-tasks/lab-10-mtu-pmtu.md).** Constrained-MTU link causing `ping -M do` failures. ICMP Fragmentation Needed triggering the kernel PMTU cache.

**[Lab A03 — NTP, Syslog, and LLDP](../labs/lab-a03-admin-tasks/lab-11-services.md).** `chrony` NTP with a local-stratum server. `rsyslog` TCP forwarding verified with a test token. `lldpd` with per-namespace sockets discovering neighbors in both directions.

**[Lab A03 — The Linux Appliance](../labs/lab-a03-admin-tasks/lab-12-appliance.md).** Full `wan–r–lan` topology: forwarding, masquerade, DNAT, stateful ACL, and DHCP. `iperf3` load test with `ip -s -s link` counter verification and `conntrack` inspection.

## How LLM agents fit here

The frame from [[article-01-linux-for-network-engineers|Article 1]] still holds: the agent is a translator and explainer, not an actor. You type every command. What changes in Article 3 is the *prompt shape*.

When you knew only `ip` commands, your prompts were one-shot: "show me the equivalent of `show ip route`." Now that you are configuring `nftables` rules, bonding modes, and VRF tables, the prompts are multi-step and benefit from a verification request in the same query:

> "On Linux, how do I configure NAT masquerade for a namespace acting as a router? Show me the nft commands and then the conntrack command I would use to confirm a NAT flow exists. Tell me what good output looks like."

That last sentence — "tell me what good output looks like" — is the habit that pays off. When you run the verification command and the output matches the agent's prediction, the configuration worked. When it doesn't match, you have a concrete discrepancy to investigate rather than a vague "why doesn't this work."

A second useful pattern for this article's tasks:

> "I need to configure reverse-path filtering on a multi-homed Linux host. List the rp_filter values and what each means, then explain when strict mode would cause problems with ECMP routing. Do not write any commands yet."

Menu first, implications second, commands third. The menu catches mismatches between what you thought you needed and what the task actually requires.

Article 11 ([[article-12-containerlab]]) is where the agent gets its hands on real tools. Article 22 ([[article-23-mcp]]) is where it gains persistent access to your infrastructure. Until then, the keyboard stays with you.

## What you should be able to do now

- Inspect the routing table, read the `proto` field, and run `ip route get` to identify the actual next-hop for a specific destination.
- Add ECMP multipath routes and metric-based failover routes; explain the difference between the two.
- Write an `nftables` forward chain with `policy drop` and `ct state established,related accept` from scratch.
- Configure NAT masquerade outbound and DNAT inbound, and use `conntrack -L` to verify active flow state.
- Set up a VLAN-aware bridge with `pvid`, tagged trunk ports, and separate VLAN broadcast domains.
- Bond two interfaces in active-backup and 802.3ad mode, and read `/proc/net/bonding/` to confirm the result.
- Mirror a port to a monitor interface using `tc clsact` and `mirred`.
- Run `dnsmasq` as a DHCP server and `dhcrelay` as a relay across subnets.
- Create VRFs, enslave interfaces, and verify routing isolation between VRFs.
- Configure `rp_filter` strict mode, describe when it causes drops, and identify the correct `nstat` counter.
- Set static and proxy ARP entries; explain when proxy ARP is appropriate.
- Probe path MTU with `ping -M do -s`, read the kernel PMTU cache from `ip route get`.
- Configure `chrony`, `rsyslog` TCP forwarding, and `lldpd` in a lab environment.
- Run `ip -s -s link`, `ss -s`, `conntrack -S`, and `nstat -a` as a first-response health sweep.
- Assemble the above into a functioning router/NAT/DHCP/ACL appliance from a bare Linux namespace.

## What comes next

[[article-04-routing-daemons]] is the next article. The tasks above are static configuration: routes you add by hand, rules that do not adapt to topology changes. Article 4 introduces **FRR** (Free Range Routing) — the open-source routing daemon that runs OSPF, BGP, BFD, and VRRP on a Linux box. Once FRR is running, the routing table fills itself, routes converge on failure, and the box starts to behave like a proper network device rather than a statically-configured host. Article 4 also covers persistence via `systemd-networkd` and the `nftables` depth that Article 1 deferred.
