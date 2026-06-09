
# Routing Daemons (Linux as a Router)

[[article-01-linux-for-network-engineers|Article 1]] gave you the translation table and the mental model that the Linux kernel's routing table is the FIB, and that if no routing daemon is running, the routes you installed by hand are the whole picture. [[article-02-interfaces-namespaces-topologies|Article 2]] showed you how to build namespaces, veth pairs, and a working forwarding topology from primitives. [[article-03-common-network-admin-tasks|Article 3]] catalogued twenty-one recurring jobs. This article is the answer to the question Article 1 left open: if the kernel is just the FIB, where does the RIB live, and how do you run real protocols against a Linux box the same way you have been running them on routers for the last twenty years?

The short answer is FRR — Free Range Routing. It runs OSPF, BGP (including BGP unnumbered, BFD, and VRRP via `keepalived` or `vrrpd`), and PIM-SM multicast, all under a unified CLI that will feel very familiar the first time you type `enable` at the `vtysh` prompt. That recognition is intentional; FRR's `vtysh` is doing the same translation-table work Article 1 did, but in the other direction — it is giving you IOS-shaped output for things that live in Linux.

This is also the first foundation article where an LLM agent shifts from translator to generator. FRR configurations are verbose to write from scratch, well-documented in public data, and loudly wrong when incorrect — the session shows `Idle` or `Active` instead of `Established` and you know immediately. That combination makes it an excellent place to learn the generate-verify loop that becomes the operating pattern for every configuration-heavy article after this one.

The production-hardening half of what this article originally promised — `systemd-networkd` persistence, `nftables` at scale, sysctl and NIC tuning, QoS, and a structured troubleshooting workflow — lives in [[article-05-production-appliance]]. The two articles were originally one, and the split reflects how much depth each half deserves. Article 4 is the routing-protocol and first-hop-redundancy and multicast article. Article 5 is the "now make it survive a reboot and stay stable under load" article.

## Routing daemons on Linux

### Why a daemon at all

The Linux kernel forwards packets. It decides where to send them by looking up the destination in the FIB — the kernel routing table — and it installs entries there via the `RTM_NEWROUTE` netlink message. When you type `ip route add 10.0.0.0/8 via 10.1.0.1`, that is precisely what happens: iproute2 sends an `RTM_NEWROUTE` message to the kernel, and the kernel updates the FIB. That route will stay there until the box reboots or you delete it.

A routing daemon does the same thing, programmatically. OSPF, BGP, IS-IS, and PIM each calculate the correct set of routes given the protocol state (link-states, path advertisements, topology convergence), and they install those routes into the kernel FIB the same way `ip route add` does. The difference is that the daemon removes and reinstalls routes as the network changes, handles timers and retransmissions, and holds the protocol state machines — the adjacency database, the LSDB, the RIB — entirely in user space.

This is the **RIB-vs-FIB split** that Article 1 flagged and that this article finally makes concrete:

| What | Lives | Query |
|---|---|---|
| FIB — the kernel's forwarding table | Kernel | `ip route show` / `ip route show proto bgp` |
| RIB — the daemon's route database | User space (`bgpd`, `ospfd`) | `vtysh -c 'show ip bgp'` / `vtysh -c 'show ip ospf database'` |

When a daemon learns a route through BGP, it puts it in `bgpd`'s RIB first. If best-path selection favors that route and the administrative distance wins against competing protocols, `zebra` (FRR's routing manager) installs it into the kernel FIB. At that point, `ip route show` shows the route with `proto bgp`. If you have not finished configuring BGP and the session is still down, the route exists in `bgpd`'s RIB but is absent from the kernel FIB — which is why "it shows up in `show ip bgp` but not `ip route show`" is a normal debugging observation, not a contradiction.

**Watch out for:** `ip route show` *always* shows the FIB — what the kernel will actually use. If a route is in the daemon's RIB but not the FIB, it will not forward packets. The two queries are not interchangeable.

### The ecosystem

**FRR** (Free Range Routing) is the default for this series. It grew out of the Quagga fork that Cumulus Networks maintained, and is now the reference implementation for vendor-neutral Linux routing. It speaks OSPF (v2 and v3), BGP (including EVPN, flowspec, and BGP-LS), IS-IS, BFD, PIM-SM, VRRP, and a handful of others. The unified `vtysh` CLI is its most useful feature for an engineer coming from IOS.

**BIRD** (BIRD Internet Routing Daemon) is lighter than FRR, popular at IXPs and in BGP-only deployments, and has a config syntax of its own that does not look like IOS. Worth knowing it exists; this series uses FRR.

**GoBGP** is a programmable BGP implementation with a gRPC API, used in some modern network controllers. No OSPF, no PIM. Worth knowing it exists when you get to [[article-17-vxlan-evpn]].

FRR is organized as one daemon per protocol, plus a routing manager:

| Daemon | Protocol |
|---|---|
| `zebra` | Routing manager — installs/removes routes in the kernel FIB. Required. |
| `bgpd` | BGP (iBGP, eBGP, EVPN, flowspec) |
| `ospfd` | OSPFv2 |
| `ospf6d` | OSPFv3 |
| `isis` | IS-IS |
| `bfdd` | Bidirectional Forwarding Detection |
| `pimd` | PIM-SM multicast |
| `vrrpd` | VRRP |
| `staticd` | Static route daemon (needed even for static routes when FRR manages them) |
| `watchfrr` | Supervisor — starts and monitors all enabled daemons |

You enable the daemons you need in `/etc/frr/daemons` (one flag per daemon, `yes`/`no`), and `watchfrr` starts them in dependency order.

## The FRR primer

### Installing FRR

On Ubuntu/Debian (the workbench image already has this):

```bash
apt-get install frr frr-pythontools
```

Enable the daemons you need in `/etc/frr/daemons`:

```bash
# /etc/frr/daemons — change "no" to "yes" for what you need
zebra=yes
bgpd=yes
ospfd=yes
bfdd=yes
pimd=no       # enable when you need multicast
vrrpd=no      # enable when you need FRR's VRRP
```

Start or restart FRR:

```bash
systemctl enable --now frr   # default single-instance mode
```

In the routing lab, each namespace runs its own FRR instance via a template unit (`frr@r1.service`, `frr@r2.service`, `frr@r3.service`) started by `setup.sh`. The template unit passes `--pathspace r1` to FRR so that each instance uses separate socket paths at `/run/frr/r1/`, `/run/frr/r2/`, `/run/frr/r3/`.

### `vtysh` — the unified CLI

`vtysh` is the Cisco-shaped shell over all FRR daemons. In the lab, connect to a namespace's FRR with:

```bash
ip netns exec r1 vtysh -N r1   # -N selects the pathspace (socket set)
```

Or use the wrapper shipped in the container:

```bash
/lab/frrvtysh r1               # equivalent shorthand
```

The prompt looks like:

```
r1# 
```

From there:

```
r1# show ip route              # FRR's view of the RIB+FIB
r1# show ip bgp                # BGP RIB
r1# show ip ospf neighbor      # OSPF adjacency state
r1# configure terminal
r1(config)# interface r1-r2
r1(config-if)# ip ospf area 0
r1(config-if)# exit
r1(config)# end
r1# write
```

`write` (or `write memory` — both work) saves the running config to `/etc/frr/r1/frr.conf`. `show running-config` displays it. `show ip route` in `vtysh` shows both the RIB entries FRR is aware of and what it has sent to the kernel — it is *not* the same as `ip route show`, which only shows the kernel FIB.

**Verify:**

```bash
ip netns exec r1 vtysh -N r1 -c 'show version'    # FRR version and enabled daemons
ip netns exec r1 vtysh -N r1 -c 'show ip route'   # combined RIB view
ip -n r1 route show                                # kernel FIB only
```

**Watch out for:** `vtysh` connects to daemons over Unix sockets. If a daemon is not running, `vtysh` will still open a prompt but some `show` commands will fail with `% Can't connect to bgpd`. `watchfrr` is what monitors daemon health and restarts crashed daemons — check `systemctl status frr@r1` before blaming `vtysh`.

### On the IOS mapping

Every `enable / configure terminal / exit / write memory` pattern you know applies. `show ip route` exists. `show ip bgp summary` exists. `show ip ospf neighbor` exists. The output is shaped like IOS output because that is the design intent — the same output your eyes already parse, from a free open-source implementation, on a Linux box you own. The translation table for this section:

| Cisco IOS | FRR `vtysh` |
|---|---|
| `show ip route` | `show ip route` |
| `show ip bgp summary` | `show ip bgp summary` |
| `show ip ospf neighbor` | `show ip ospf neighbor` |
| `show ip ospf database` | `show ip ospf database` |
| `debug ip ospf adj` | `debug ospf nsm` |
| `write memory` | `write` |
| `copy running-config startup-config` | `write` |

The things that differ: there is no `show tech-support`, no `show processes`, no `show version` that lists the box's serial number. Those live in other Linux tools or are not relevant. The routing-specific `show` commands are almost all present and produce recognizable output.

## First OSPF adjacency

The topology for the routing lab is `r1 — r2 — r3`: three namespaces connected by veth pairs, FRR running in each. `setup.sh` builds this topology and starts `frr@r1/r2/r3`. After running `setup.sh`:

```
10.0.0.1/32 (r1 lo)   10.0.0.2/32 (r2 lo)   10.0.0.3/32 (r3 lo)
       r1 ——[10.0.12.0/24]—— r2 ——[10.0.23.0/24]—— r3
```

To bring up OSPF between `r1` and `r2`:

```bash
# On r1
ip netns exec r1 vtysh -N r1 -c "
configure terminal
router ospf
 ospf router-id 10.0.0.1
 network 10.0.12.0/24 area 0
 network 10.0.0.1/32 area 0
 passive-interface r1-lo
end
write
"

# On r2
ip netns exec r2 vtysh -N r2 -c "
configure terminal
router ospf
 ospf router-id 10.0.0.2
 network 10.0.12.0/24 area 0
 network 10.0.23.0/24 area 0
 network 10.0.0.2/32 area 0
 passive-interface r2-lo
end
write
"
```

Watch the adjacency form. OSPF progresses through states — you can see each one:

```bash
ip netns exec r1 vtysh -N r1 -c 'show ip ospf neighbor'
```

You should see the state move from `Init` → `2-Way` → `ExStart` → `Exchange` → `Loading` → `Full`. If `r1` and `r2` are directly connected and OSPF is configured on both sides, `Full` should appear within a few seconds.

**Verify:**

```bash
# OSPF adjacency is Full
ip netns exec r1 vtysh -N r1 -c 'show ip ospf neighbor'

# r2's loopback route appeared in r1's FIB — this is where RIB-vs-FIB becomes concrete
ip -n r1 route show proto ospf

# Ping r2's loopback (through the kernel FIB, not the OSPF RIB)
ip netns exec r1 ping -c 3 10.0.0.2
```

```bash
# LSDB — what OSPF knows, independent of what the kernel forwarded
ip netns exec r1 vtysh -N r1 -c 'show ip ospf database'
```

**Watch out for:** if the adjacency stays in `Init` or `2-Way` and never reaches `Full`, check that `ip_forward` is set in each namespace — OSPF will not send hellos properly if the interface it is on cannot forward packets. Also check that the OSPF network statement matches the actual interface subnet. A mismatch here (e.g., OSPF advertises `10.0.12.0/24` but the interface is `10.0.12.1/30`) causes a silent non-adjacency that is not easy to see in `show ip ospf neighbor`.

Extend OSPF to cover the full triangle by adding `r3`:

```bash
# On r3
ip netns exec r3 vtysh -N r3 -c "
configure terminal
router ospf
 ospf router-id 10.0.0.3
 network 10.0.23.0/24 area 0
 network 10.0.0.3/32 area 0
 passive-interface r3-lo
end
write
"
```

After convergence, `r1` should have routes to `10.0.0.2/32`, `10.0.23.0/24`, and `10.0.0.3/32` via OSPF, and `r1`'s kernel FIB should reflect all of them.

## First BGP session

eBGP between `r1` and `r3` over the OSPF-learned underlay. `r1` is in AS 65001, `r3` is in AS 65003.

```bash
# On r1
ip netns exec r1 vtysh -N r1 -c "
configure terminal
router bgp 65001
 bgp router-id 10.0.0.1
 neighbor 10.0.0.3 remote-as 65003
 neighbor 10.0.0.3 update-source r1-lo
 !
 address-family ipv4 unicast
  network 10.0.0.1/32
  neighbor 10.0.0.3 activate
 exit-address-family
end
write
"

# On r3
ip netns exec r3 vtysh -N r3 -c "
configure terminal
router bgp 65003
 bgp router-id 10.0.0.3
 neighbor 10.0.0.1 remote-as 65001
 neighbor 10.0.0.1 update-source r3-lo
 !
 address-family ipv4 unicast
  network 10.0.0.3/32
  neighbor 10.0.0.1 activate
 exit-address-family
end
write
"
```

**Verify:**

```bash
# BGP session state — the line you are looking for is Established, Uptime counting up
ip netns exec r1 vtysh -N r1 -c 'show ip bgp summary'

# r3's loopback appeared in BGP RIB on r1
ip netns exec r1 vtysh -N r1 -c 'show ip bgp'

# And it landed in the kernel FIB — this is the RIB-to-FIB promotion step
ip -n r1 route show proto bgp
```

The output of `show ip bgp summary` should show `10.0.0.3/32` in the `Up/Down` column with a time (not `never`) and `Established` for state. If the session shows `Idle` or `Active`, it is not up. `Idle` means BGP is not trying to connect (check the neighbor address or AS). `Active` means it is trying and failing (check that the underlay OSPF route exists so the two loopbacks can reach each other).

**Watch out for:** eBGP multi-hop. If you are peering over loopbacks (as in this lab), BGP expects the TTL to be 1 on the received packet but the packet arrives with a lower TTL after crossing multiple hops. Add `neighbor 10.0.0.3 ebgp-multihop 2` (or however many hops the path crosses) if the session stays in `Active` with a reachable peer address. In this topology `r1` and `r3` are two hops apart through `r2`, so `ebgp-multihop 2` is required.

## BGP unnumbered

BGP unnumbered is the data-center fabric convention: run BGP over IPv6 link-local addresses instead of manually configured IPv4 peer addresses. Every modern spine-leaf fabric (Cumulus, SONiC, most Arista EOS data-center deployments) uses this by default. The reader who gets to [[article-17-vxlan-evpn]] will find it everywhere.

The reason it exists: on a spine-leaf fabric with forty leaf nodes, configuring a manual IPv4 peer address per link pair is forty times the management surface. IPv6 link-local addresses auto-assign from the MAC, so there is nothing to provision. BGP simply says "peer with whoever I see on this interface."

Tear down the numbered BGP session from §4 and rebuild it unnumbered:

```bash
# On r1 — remove the numbered session, add unnumbered
ip netns exec r1 vtysh -N r1 -c "
configure terminal
no router bgp 65001
router bgp 65001
 bgp router-id 10.0.0.1
 neighbor r1-r2 interface remote-as external
 !
 address-family ipv4 unicast
  network 10.0.0.1/32
  neighbor r1-r2 activate
 exit-address-family
 !
 address-family ipv6 unicast
  neighbor r1-r2 activate
 exit-address-family
end
write
"

# On r2 — in the middle, peer with both r1 and r3
ip netns exec r2 vtysh -N r2 -c "
configure terminal
router bgp 65002
 bgp router-id 10.0.0.2
 neighbor r2-r1 interface remote-as external
 neighbor r2-r3 interface remote-as external
 !
 address-family ipv4 unicast
  network 10.0.0.2/32
  neighbor r2-r1 activate
  neighbor r2-r3 activate
 exit-address-family
 !
 address-family ipv6 unicast
  neighbor r2-r1 activate
  neighbor r2-r3 activate
 exit-address-family
end
write
"

# On r3 — mirror of r1
ip netns exec r3 vtysh -N r3 -c "
configure terminal
no router bgp 65003
router bgp 65003
 bgp router-id 10.0.0.3
 neighbor r3-r2 interface remote-as external
 !
 address-family ipv4 unicast
  network 10.0.0.3/32
  neighbor r3-r2 activate
 exit-address-family
 !
 address-family ipv6 unicast
  neighbor r3-r2 activate
 exit-address-family
end
write
"
```

The key line is `neighbor r1-r2 interface remote-as external`. No IP address is configured — FRR discovers the peer's IPv6 link-local address from the interface and uses it as the next-hop.

**Verify:**

```bash
# Session is Established
ip netns exec r1 vtysh -N r1 -c 'show ip bgp summary'

# The peer is identified by interface name, not IP
ip netns exec r1 vtysh -N r1 -c 'show bgp neighbors r1-r2'

# r3's loopback is in the FIB on r1 — IPv4 prefix arrived over an IPv6 link-local transport
ip -n r1 route show proto bgp

# Confirm the next-hop is an IPv6 link-local address
ip netns exec r1 vtysh -N r1 -c 'show ip bgp'
```

**Watch out for:** IPv6 must be enabled on the interfaces you are using. Linux does not auto-enable IPv6 on every interface if `net.ipv6.conf.all.disable_ipv6=1` is set. In the lab container, IPv6 is enabled by default. If you see the session stuck at `Idle` on the unnumbered config, check `ip -6 addr show dev r1-r2` — there must be a link-local `fe80::` address present.

## BFD with FRR

BGP's default holdtime is 90 seconds (three keepalive misses at 30 seconds each). OSPF's dead interval defaults to 40 seconds. In a real network, that means a link failure takes up to a minute and a half to converge BGP — which is unacceptable. BFD (Bidirectional Forwarding Detection) is the sub-second failure detector that sits underneath the routing protocol and reports "the neighbor is gone" in milliseconds.

FRR's `bfdd` daemon implements BFD. Enable it in `/etc/frr/<ns>/daemons`, then wire it to an existing BGP or OSPF session:

```bash
# On r1 — add BFD to the BGP neighbor
ip netns exec r1 vtysh -N r1 -c "
configure terminal
router bgp 65001
 neighbor r1-r2 bfd
end
write
"

# Do the same on r2
ip netns exec r2 vtysh -N r2 -c "
configure terminal
router bgp 65002
 neighbor r2-r1 bfd
 neighbor r2-r3 bfd
end
write
"
```

BFD negotiates the detection timer between the two endpoints. The default interval is 300ms with a detect multiplier of 3, giving a 900ms detection time. For the lab, tighten it to 100ms / multiplier 3 (300ms detection):

```bash
ip netns exec r1 vtysh -N r1 -c "
configure terminal
bfd
 peer r1-r2 interface r1-r2
  receive-interval 100
  transmit-interval 100
  detect-multiplier 3
end
write
"
```

**Verify:**

```bash
# BFD peers and their state — look for "Status: Up"
ip netns exec r1 vtysh -N r1 -c 'show bfd peers'

# BGP neighbor carries a BFD reference
ip netns exec r1 vtysh -N r1 -c 'show bgp neighbors r1-r2' | grep -A5 BFD
```

The failover-time lab exercise (Lab A04 routing, section 5) measures the BGP reconvergence time with and without BFD by inducing a link failure and timing `ip route get 10.0.0.3` in a loop until the route returns. The delta — tens of seconds versus sub-second — makes BFD's value concrete. The checker does not flap anything (non-destructive rule); the measurement is a reader exercise.

**Watch out for:** BFD requires both sides to agree on the interval. If one side sets 100ms and the other is still at the 300ms default, the effective detection time will be the maximum of the two. Also, BFD runs its own keepalives independently of the routing protocol — a `clear bgp *` event that resets the BGP session will not appear in BFD's state machine at all, because the link stayed up. This is intentional (and Section 8 shows the difference via journalctl).

## First-hop redundancy: VRRP

The IOS model is HSRP or VRRP: two boxes share a virtual IP, one is MASTER, the other is BACKUP, and the BACKUP takes over when the MASTER fails. On Linux, the standard tool is **`keepalived`**, which implements VRRPv2 and v3 directly and is what every off-the-shelf Linux router appliance (VyOS, OPNsense, pfSense) uses under the hood. FRR also ships a `vrrpd` daemon for shops already running FRR for routing.

The conceptual lift from IOS is minimal. `keepalived.conf` looks like a Cisco `interface` block with `vrrp` lines. The differences worth knowing:

- There is no GLBP equivalent on Linux. For active-active first-hop with a single VIP, use ECMP at L3 or a load balancer at L4 — active-active from a single virtual IP is not a Linux concept.
- VRRP advertisement intervals in VRRPv2 are in whole seconds. Sub-second failover requires VRRPv3 (`version 3` in keepalived, `vrrp NN version 3` in FRR's vtysh) with tuned intervals.
- The virtual IP appears in `ip addr show` on the MASTER. It is not a phantom address — the MASTER responds to ARP for it and the BACKUP does not.

Full exercise in **[Lab A04 — VRRP](../labs/lab-a04-vrrp/)**. That lab covers both `keepalived` and FRR `vrrpd` against the same topology.

## Persisting FRR

Every `vtysh` change takes effect immediately and is lost at daemon restart if you do not save it. `write` (or `write memory`) persists the running config to `/etc/frr/<ns>/frr.conf`:

```bash
ip netns exec r1 vtysh -N r1 -c 'write'
cat /etc/frr/r1/frr.conf     # looks exactly like a Cisco config
```

The file is what FRR loads at startup. Verify persistence by restarting a daemon:

```bash
systemctl restart frr@r1
# Wait a few seconds for watchfrr to restart all daemons
systemctl status frr@r1
ip netns exec r1 vtysh -N r1 -c 'show ip bgp summary'   # session should re-establish
```

FRR's config model has two modes. By default each daemon writes its own file (`zebra.conf`, `bgpd.conf`, etc.). The `integrated-vtysh-config` option (set in `/etc/frr/vtysh.conf`) causes `write` to produce a single `frr.conf` that covers all daemons — this is the modern default and what the lab uses.

**Watch out for:** a syntax error in `frr.conf` causes the relevant daemon to fail to start. If `systemctl restart frr@r1` results in a crash, check `journalctl -u frr@r1 -e` — FRR logs the line number and error before exiting. Fix the file and restart again. There is no `commit validated` equivalent; FRR's validation happens at load time. The lab exercises this deliberately: after confirming persistence works, the walkthrough asks you to introduce a syntax error into `frr.conf` and watch the daemon fail, so you recognize the error output when you encounter it in production.

General-purpose network persistence (making `ip addr add` and `ip route add` survive reboots, persisting `nftables` rules across restarts) is covered in [[article-05-production-appliance]] §1–2. FRR's persistence story is self-contained here because it has its own gotchas (per-daemon files vs. integrated config, `watchfrr` ordering) that do not generalize.

## Multicast routing with FRR `pimd`

On IOS: `ip multicast-routing`, `ip pim sparse-mode` on each interface, and a rendezvous point. On Linux: FRR's `pimd`, which speaks PIM-SM (RFC 7761) and integrates with the same `vtysh` you used for OSPF and BGP.

Two sysctls you must set in the routing namespace before any multicast forwarding can happen — and these must be set **in addition to** `ip_forward`, because multicast forwarding is separately gated:

```bash
ip netns exec r1 sysctl -w net.ipv4.ip_forward=1
ip netns exec r1 sysctl -w net.ipv4.conf.all.mc_forwarding=1
```

Enable `pimd` in the daemons file, then configure via `vtysh`:

```bash
ip netns exec r1 vtysh -N r1 -c "
configure terminal
ip multicast-routing
interface r1-src
 ip pim
 ip igmp
exit
interface r1-dst
 ip pim
 ip igmp
exit
ip pim rp 10.30.1.1 224.0.0.0/4
end
write
"
```

The IOS-to-Linux mapping:

| Cisco IOS | FRR `vtysh` |
|---|---|
| `ip multicast-routing` | `ip multicast-routing` |
| `ip pim sparse-mode` (per interface) | `ip pim` (per interface in FRR) |
| `ip pim rp-address 10.0.0.1` | `ip pim rp 10.0.0.1 224.0.0.0/4` |
| `show ip pim neighbor` | `show ip pim neighbor` |
| `show ip mroute` | `show ip mroute` |
| `show ip igmp groups` | `show ip igmp groups` |
| `ip mroute` (static, for smcroute) | `smcroute -a <iif> <src> <grp> <oif>` |

IGMP is handled by the kernel — `ip maddr show` lists per-interface group memberships. The multicast FIB (`ip mroute show`) is also in the kernel. FRR's `pimd` handles the PIM control plane, including the RP discovery and the `(S,G)` state machine.

**Watch out for:** there can only be one process per namespace holding the multicast forwarding socket. If `pimd` and `smcroute` are both running in the same namespace, the second one to start will fail to bind with `ENXIO` or similar. Run one or the other, not both.

Full exercise in **[Lab A04 — Multicast](../labs/lab-a04-multicast/)**, which walks through both PIM-SM with `pimd` and the static `smcroute` case.

## Reading what just happened: `journalctl` against a live FRR session

Article 1 promised that `journalctl` is the tool that unifies many writers, and that a single network event produces entries from the kernel and the routing daemon milliseconds apart. This section delivers that lesson against a live FRR session.

The mapping table:

| Cisco IOS | Linux journal |
|---|---|
| `show logging` | `journalctl -e` |
| `show logging \| include OSPF` | `journalctl -u ospfd` (or `-u frr@r1`) |
| `show logging \| include LINK` | `journalctl -k -g 'link is'` |
| `terminal monitor` | `journalctl -u 'frr@*' -f` |
| (no equivalent) | `journalctl -o json-pretty \| jq '…'` (structured query) |

### The three-shell exercise

Open three shells into the routing lab container (or use `tmux` splits inside the workbench):

**Shell 1 — watch FRR events:**
```bash
journalctl -u 'frr@*' -f
```

**Shell 2 — watch kernel link events:**
```bash
dmesg -wT
```

**Shell 3 — control shell:**
```bash
# Flap the link between r1 and r2
ip link set r1-r2 down
sleep 2
ip link set r1-r2 up
```

In shell 2 you will see the kernel log the link transition first — `r1-r2: Link is Down` — immediately. In shell 1, `ospfd` or `bgpd` logs the adjacency or session reset a few milliseconds later. Bring the link back up and you see the inverse: kernel logs link-up, then FRR logs the adjacency reforming through its state machine.

### The daemon-only event

```bash
# In shell 3 — reset BGP without touching the link
ip netns exec r1 vtysh -N r1 -c 'clear bgp *'
```

Shell 2 (kernel) sees nothing — the link is still up. Shell 1 (FRR) logs the BGP session reset, the re-OPEN, and the re-establishment. This is the "many writers" distinction: a daemon-internal event leaves no kernel trace. If you are trying to correlate "why did the BGP session drop" and the kernel log shows nothing, the answer is probably inside the daemon.

### The structured query

```bash
journalctl --since '2 min ago' \
  -o json-pretty \
  | jq 'select(._SYSTEMD_UNIT == "frr@r1.service"
           or .SYSLOG_IDENTIFIER == "kernel")
        | {t: .__REALTIME_TIMESTAMP, u: ._SYSTEMD_UNIT, m: .MESSAGE}'
```

This query interleaves FRR and kernel journal entries in timestamp order, filtered to the unit and the kernel, with only the three fields you care about. It is the Linux equivalent of `show logging | include` run against both writers at once.

`nftables` log rules (from Article 3) also appear in this stream under `SYSLOG_IDENTIFIER="nft_log"`. When an `nft ... log prefix "FORWARD-DROP:"` rule fires, it shows up in `journalctl -f` the same way an FRR adjacency message does — the journal is the unified bus, and every writer appears there. This is the first concrete demonstration in the series that the journal handles all of them at once.

**Watch out for:** in the container workbench, `journalctl` works because systemd is running as PID 1. If you replicate this exercise on a system that uses a different init (Debian with sysvinit, some minimal container images), the FRR units may not be in the journal at all — FRR would log to `/var/log/frr/` instead and you would need to `tail -f` those files. The series workbench runs systemd deliberately so the journal lesson lands the way it is intended.

## The labs

Three lab directories pair with this article. They share a single container (`containers/article-04/`) that runs systemd and FRR.

**[Lab A04 — Routing](../labs/lab-a04-routing/)** — seven chained sub-labs on the `r1—r2—r3` topology. Build the topology once with `setup.sh`, then work through:

1. RIB vs FIB (§§1–2) — two queries, two data stores
2. First OSPF adjacency (§3) — adjacency states, LSDB, kernel FIB via OSPF
3. First BGP session (§4) — eBGP over loopbacks, `show ip bgp summary`, FIB promotion
4. BGP unnumbered (§5) — interface-based peers, IPv6 link-local transport, IPv4 prefix delivery
5. BFD-accelerated failover (§5a) — BFD peers, sub-second detection, timing exercise
6. Persisting FRR (§6) — `write`, config survives restart, intentional syntax error
7. Journal correlation (§8) — three-shell flap exercise, daemon-only event, structured jq query

Tests: `./tests/routing/test.sh <N>` — non-destructive, auto-discovers namespace roles.

**[Lab A04 — VRRP](../labs/lab-a04-vrrp/)** — two sub-labs on a `r1/r2/lan` topology:

1. `keepalived` — VIP ownership, VRRP advertisements, failover observation
2. FRR `vrrpd` — same semantics, single-daemon approach

Tests: `./tests/vrrp/test.sh <N>`

**[Lab A04 — Multicast](../labs/lab-a04-multicast/)** — two sub-labs on a `src/r1/dst` topology:

1. FRR `pimd` PIM-SM — IGMP join, `(S,G)` state, multicast FIB
2. `smcroute` static mroute — static forwarding without a control plane

Tests: `./tests/multicast/test.sh <N>`

Start the workbench:

```bash
docker compose -f containers/article-04/docker-compose.yml run --rm lab
```

Inside the container:

```bash
/lab/setup.sh               # build the r1-r2-r3 routing topology
systemctl status frr@r1     # confirm FRR is running in r1
./tests/routing/test.sh     # list available routing lab checks
```

## How LLM agents fit here

This is the first foundation article where the agent is genuinely *generative*, not just a translator. FRR configurations are verbose to write by hand, well-documented in public materials, and easy to verify. The agent's right job: take a one-paragraph intent and produce a config block the reader can paste.

The prompt shape that works:

> "Write a FRR `vtysh` configuration for eBGP between two Linux namespaces. AS 65001 is on `r1` with router-id `10.0.0.1` and loopback `10.0.0.1/32`. AS 65003 is on `r3` with router-id `10.0.0.3` and loopback `10.0.0.3/32`. They peer over loopbacks with `ebgp-multihop 2`. Each should advertise only its own loopback. No IPv6, no route-reflectors. Produce the `configure terminal` block for each router."

The answer is a config block you paste into `vtysh -N r1 -f`. The verification is immediate: `show ip bgp summary` either shows `Established` or it does not. If it shows `Active`, you ask the agent to read the `show bgp neighbors` output and identify why. The loop is: generate → paste → verify → if wrong, show the agent the output and iterate.

This is the generate-verify loop you will use for every configuration-heavy article in the series from here on. The verification habit from earlier articles (Article 1: read the output and check if it makes sense; Articles 2 and 3: run the test script) becomes load-bearing here because a mistyped AS number or a wrong `update-source` produces a session that looks almost right but never reaches `Established`.

What the agent is not doing: it is not running `vtysh`. It is not inside your namespace. It is not reading your `ip route show`. You are. The agent generates; you execute; verification happens at your prompt. Agent tool use enters the series at [[article-12-containerlab]] and becomes full-throated at [[article-23-mcp]]. The parallel generative use case for `nftables` rule sets is in [[article-05-production-appliance]].

## What you should be able to do now

- Open `vtysh` in a namespace, recognize the prompt, type `show ip bgp summary`, and read the output the way you would read a Cisco router's BGP neighbor table.
- Distinguish the FIB (`ip route show proto bgp`) from the RIB (`vtysh show ip bgp`) and explain the promotion step in one sentence.
- Configure OSPF and eBGP between two FRR instances from memory, verify the adjacency and session, and confirm the routes arrived in the kernel FIB.
- Explain what `neighbor r1-r2 interface remote-as external` does and why modern data-center fabrics use it instead of numbered peers.
- Wire BFD to an existing BGP or OSPF session and measure the failover improvement.
- Type `write` after every change and confirm the config survived `systemctl restart frr@<ns>`.
- Run a three-shell journal exercise against a live FRR topology — flap a link, watch both the kernel and the daemon log the event, pull both writers into a single structured jq query.
- Give an LLM a one-paragraph intent and produce a working FRR config block that reaches `Established` after pasting.

## What comes next

[[article-05-production-appliance]] is the hardening article — everything this article deferred. `systemd-networkd` for making addresses and routes survive reboots. `nftables` in depth: hooks, families, sets, maps, the NAT chain architecture, and a full appliance ruleset from scratch. Sysctl and NIC tuning: `net.ipv4.tcp_bbr`, ring buffers, checksum offload, RSS. QoS with `tc` and HTB. And a structured troubleshooting workflow (`ip monitor`, `ss`, `ethtool`, `bpftrace`). When you finish Article 5, the Linux foundation cluster is complete.
