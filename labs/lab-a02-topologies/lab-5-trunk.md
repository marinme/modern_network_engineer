# Lab A02 — Trunks: carrying VLANs between switches

Part of **[Lab A02 — Topologies from `iproute2`](./README.md)**. Read the README first for the [container setup](./README.md#the-setup), prerequisites, and persistence/cleanup conventions — every command below runs inside that one Docker workbench at the `root@workbench:/lab#` prompt. This lab assumes the VLAN-filtering idea from [Lab 2](./lab-2-switch.md) and pairs naturally with the SVIs from [Lab 4](./lab-4-svi.md).

Two VLAN-aware bridges in separate namespaces (`sw1`, `sw2`) joined by a single **trunk**: one veth pair whose bridge ports carry both VLANs, tagged. Two VLANs span the pair of switches — `a1`/`a2` in VLAN 10, `b1`/`b2` in VLAN 20, one host of each VLAN on each switch. By the end, same-VLAN hosts reach each other *across* the trunk, different VLANs stay isolated, and `tcpdump` shows the 802.1Q tag that makes it work.

A trunk is not a special device. It is an ordinary veth whose bridge ports are members of more than one VLAN in **tagged** mode (no `pvid untagged`). The 802.1Q tag on each frame is the only thing multiplexing the VLANs down the one wire.

![Lab 5 topology: two VLAN-aware bridges sw1 and sw2 joined by one 802.1Q trunk carrying VLANs 10 and 20 tagged; a1/a2 in VLAN 10 (blue) and b1/b2 in VLAN 20 (purple), one of each per switch, so same-VLAN hosts reach across the trunk while different VLANs stay isolated](assets/art02-lab5-trunk.png)

## Build

```bash
# Two switches, four hosts
for ns in sw1 sw2 a1 b1 a2 b2; do ip netns add $ns; ip -n $ns link set lo up; done

# A VLAN-aware bridge in each switch
ip -n sw1 link add br0 type bridge vlan_filtering 1; ip -n sw1 link set br0 up
ip -n sw2 link add br0 type bridge vlan_filtering 1; ip -n sw2 link set br0 up

# Host veth pairs: a1,b1 -> sw1 ; a2,b2 -> sw2
ip link add veth-a1 type veth peer name p-a1; ip link set veth-a1 netns a1; ip link set p-a1 netns sw1
ip link add veth-b1 type veth peer name p-b1; ip link set veth-b1 netns b1; ip link set p-b1 netns sw1
ip link add veth-a2 type veth peer name p-a2; ip link set veth-a2 netns a2; ip link set p-a2 netns sw2
ip link add veth-b2 type veth peer name p-b2; ip link set veth-b2 netns b2; ip link set p-b2 netns sw2

# The trunk: one veth pair between the two bridges
ip link add trunk1 type veth peer name trunk2
ip link set trunk1 netns sw1
ip link set trunk2 netns sw2

# Enslave every port to its bridge and bring up
for pp in sw1:p-a1 sw1:p-b1 sw1:trunk1 sw2:p-a2 sw2:p-b2 sw2:trunk2; do
  sw=${pp%:*}; p=${pp#*:}
  ip -n $sw link set $p master br0
  ip -n $sw link set $p up
done

# Access ports: one VLAN each, untagged toward the host
ip netns exec sw1 bridge vlan add vid 10 dev p-a1 pvid untagged
ip netns exec sw1 bridge vlan add vid 20 dev p-b1 pvid untagged
ip netns exec sw2 bridge vlan add vid 10 dev p-a2 pvid untagged
ip netns exec sw2 bridge vlan add vid 20 dev p-b2 pvid untagged

# Trunk ports: BOTH VLANs, tagged (note: no 'pvid untagged')
ip netns exec sw1 bridge vlan add vid 10 dev trunk1
ip netns exec sw1 bridge vlan add vid 20 dev trunk1
ip netns exec sw2 bridge vlan add vid 10 dev trunk2
ip netns exec sw2 bridge vlan add vid 20 dev trunk2

# Drop the default VLAN 1 from every port on both switches
for pp in sw1:p-a1 sw1:p-b1 sw1:trunk1; do sw=${pp%:*}; p=${pp#*:}; ip netns exec $sw bridge vlan del vid 1 dev $p; done
for pp in sw2:p-a2 sw2:p-b2 sw2:trunk2; do sw=${pp%:*}; p=${pp#*:}; ip netns exec $sw bridge vlan del vid 1 dev $p; done

# Host addressing — VLAN 10 in 172.16.10.0/24, VLAN 20 in 172.16.20.0/24
ip -n a1 addr add 172.16.10.11/24 dev veth-a1; ip -n a1 link set veth-a1 up
ip -n a2 addr add 172.16.10.12/24 dev veth-a2; ip -n a2 link set veth-a2 up
ip -n b1 addr add 172.16.20.11/24 dev veth-b1; ip -n b1 link set veth-b1 up
ip -n b2 addr add 172.16.20.12/24 dev veth-b2; ip -n b2 link set veth-b2 up
```

Confirm the VLAN membership on each switch:

```bash
ip netns exec sw1 bridge vlan show     # p-a1 untagged@10, p-b1 untagged@20, trunk1 tagged@10 and @20
ip netns exec sw2 bridge vlan show     # mirror image on sw2
```

The trunk port shows up in **both** VLANs without `PVID`/`Untagged` flags — that columnar difference (untagged on access ports, tagged on the trunk) is the entire definition of a trunk.

## Verify

**Same VLAN, across the trunk — works:**

```bash
ip netns exec a1 ping -c 2 172.16.10.12        # VLAN 10: sw1 → trunk → sw2
ip netns exec b1 ping -c 2 172.16.20.12        # VLAN 20: sw1 → trunk → sw2
```

**Different VLANs — isolated, even though they share the trunk:**

```bash
ip netns exec a1 ping -c 2 172.16.20.12        # VLAN 10 host → VLAN 20 host: no reply
```

`a1` and `b2` are in different VLANs (and different subnets), so there is no L2 path between them and no router to bridge the subnets. The trunk carries both VLANs' frames over the same veth, but the tag keeps them in separate broadcast domains end to end.

**See the tag on the wire — the payoff:**

```bash
ip netns exec sw1 tcpdump -i trunk1 -e -n &
ip netns exec a1 ping -c 2 172.16.10.12
ip netns exec b1 ping -c 2 172.16.20.12
kill %1
```

In the `tcpdump` output (`-e` prints link-layer headers) the VLAN 10 ping shows `vlan 10, p 0, ...` and the VLAN 20 ping shows `vlan 20, ...`. The access ports never see a tag — the host frames are plain Ethernet — but on the trunk every frame is tagged. That tag, added when the frame enters the trunk port and stripped when it leaves the far access port, is what lets one cable carry many isolated LANs.

## Test your work

From the `/lab` prompt, after building the trunked switches:

```bash
./tests/test.sh 5
```

**Verify-only and non-destructive.** It auto-discovers the two VLAN-filtering bridges, the trunk port between them, and the per-VLAN host groups, then checks the trunk's whole point: **same-VLAN** hosts reach each other across the trunk with their frames **802.1Q-tagged** (`tcpdump -e`), the two VLANs ride the trunk under **different tags**, and **cross-VLAN** hosts stay **isolated**. `PASS`/`FAIL` per check. (The `tests/` directory is mounted read-only by the compose workbench.)

## Optional extension — route between VLANs across the trunk

So far this is pure L2: two broadcast domains stretched across two switches, kept apart. To let VLAN 10 talk to VLAN 20, add a router-on-a-trunk on `sw1` using the SVI pattern from [Lab 4](./lab-4-svi.md):

```bash
# Let sw1's bridge receive both VLANs toward the CPU, then add an SVI gateway per VLAN
ip netns exec sw1 bridge vlan add vid 10 dev br0 self
ip netns exec sw1 bridge vlan add vid 20 dev br0 self
ip -n sw1 link add link br0 name br0.10 type vlan id 10
ip -n sw1 link add link br0 name br0.20 type vlan id 20
ip -n sw1 addr add 172.16.10.1/24 dev br0.10; ip -n sw1 link set br0.10 up
ip -n sw1 addr add 172.16.20.1/24 dev br0.20; ip -n sw1 link set br0.20 up
ip netns exec sw1 sysctl -w net.ipv4.ip_forward=1

# Point every host at the gateway in its VLAN
ip -n a1 route add default via 172.16.10.1
ip -n a2 route add default via 172.16.10.1
ip -n b1 route add default via 172.16.20.1
ip -n b2 route add default via 172.16.20.1

# Now a2 (VLAN 10 on sw2) can reach b2 (VLAN 20 on sw2) — the packet crosses the
# trunk to sw1's SVIs, gets routed VLAN 10 -> VLAN 20, and crosses back.
ip netns exec a2 ping -c 2 172.16.20.12
ip netns exec a2 traceroute -n 172.16.20.12     # one hop: 172.16.10.1 on sw1
```

That `traceroute` showing the gateway lives on `sw1` even though both endpoints hang off `sw2` is the "router on a stick" pattern: a single L3 hop, reached over the trunk, serves inter-VLAN routing for the whole fabric.

## Comprehension Questions
1.) In `bridge vlan show`, the access ports list their VLAN as `PVID Egress Untagged` while the trunk ports list theirs with no flags. What does that difference do to a frame as it leaves each kind of port?
2.) `a1 → b2` fails. Give two independent reasons it cannot work — one at L2 and one at L3.
3.) Which command and flag let you confirm a frame crossing the trunk is actually 802.1Q-tagged, and what would you grep for to tell a VLAN 10 frame from a VLAN 20 frame?
<details>
<summary>Answers (click to expand)</summary>

**1.** An **access** port (`PVID Egress Untagged`) **strips** the VLAN tag on egress, so the host receives plain untagged Ethernet (and `PVID` assigns that VID to untagged frames arriving from the host). A **trunk** port (the VID listed with no flags) leaves the frame **tagged**, so the switch at the far end of the trunk knows which VLAN it belongs to. Untagged toward the host, tagged across the trunk.

**2.** **L2:** `a1` (VLAN 10) and `b2` (VLAN 20) are in different broadcast domains; the trunk carries both but the tag keeps them apart, so ARP for `b2` never reaches it. **L3:** they're in different subnets (172.16.10.0/24 vs 172.16.20.0/24) with no router between the VLANs, so there's no route even if L2 worked. Either reason alone is enough — the optional extension fixes the L3 one with SVIs.

**3.** `ip netns exec sw1 tcpdump -i trunk1 -e -n` — `-e` prints the link-layer header, which includes the 802.1Q tag. Look for `vlan 10` vs `vlan 20` on the ICMP lines to tell the two VLANs apart.

</details>

## Teardown

```bash
for ns in sw1 sw2 a1 b1 a2 b2; do ip netns del $ns; done
```

---

You have now built, by hand, every shape Article 2 promised: a router, a switch, the two composed, an L3 switch with SVIs, and a trunked two-switch fabric. The persistent (Netplan / systemd-networkd) versions of this configuration are [Article 5](../../wiki/article-05-production-appliance.md); the YAML-wrapped, one-node-per-container version is [Containerlab](../../wiki/article-12-containerlab.md). Both read as "the thing I already built," which was the point.
