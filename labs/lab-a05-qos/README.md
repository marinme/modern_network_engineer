# Lab A04 — QoS with `tc`, HTB, and `fq_codel`

Pairs with: [Article 4 — Routing Daemons, Persistence, Tuning](../../wiki/article-04-routing-daemons.md)

## What this lab teaches

Traffic classification, shaping, and queueing on Linux. The Cisco mental model is MQC: `class-map` matches traffic, `policy-map` decides what to do (police, shape, queue, mark), `service-policy` attaches it to an interface. On Linux the corresponding tool is **`tc`** (traffic control), which builds a tree of **qdiscs** (queueing disciplines), **classes** (bandwidth allocations inside a hierarchical qdisc), and **filters** (the classification rules that send packets to classes).

Two qdiscs cover 90% of practical use:

- **HTB** (Hierarchical Token Bucket) is the shaper. Build a class tree with rates and ceilings; filters direct traffic into classes; HTB enforces the rates. This is the analog to `shape average` and `bandwidth percent` in MQC.
- **`fq_codel`** is the modern default queueing discipline. It's a fair-queueing CoDel hybrid that aggressively kills bufferbloat with almost no tuning. It is the right default leaf qdisc inside HTB classes and on bare interfaces. The IOS analog is WRED with sensible defaults, except `fq_codel` actually works without tuning.

Marking with DSCP, policing (drop on exceed) versus shaping (delay on exceed), and trust boundaries all map cleanly. The big mental shift: Linux qdiscs apply on **egress** by default; ingress requires a small extra ritual using `IFB` (Intermediate Functional Block) or `tc clsact` direct-action filters.

## Prerequisites

- Lab A01 finished.
- Two namespaces with a veth pair between them (we'll set up; minimal).
- `iperf3` installed for traffic generation.
- `iproute2` recent enough to have `tc -j` JSON output (Debian 11+, Ubuntu 22.04+, RHEL 9+).

## The setup

Two namespaces connected by a veth pair. We'll shape the link from `client` toward `server` and demonstrate `fq_codel` behaviour under load.

```bash
sudo ip netns add client
sudo ip netns add server
sudo ip link add c-eth0 type veth peer name s-eth0
sudo ip link set c-eth0 netns client
sudo ip link set s-eth0 netns server
sudo ip netns exec client ip addr add 10.20.0.1/24 dev c-eth0
sudo ip netns exec server ip addr add 10.20.0.2/24 dev s-eth0
sudo ip netns exec client ip link set c-eth0 up
sudo ip netns exec server ip link set s-eth0 up
sudo ip netns exec client ip link set lo up
sudo ip netns exec server ip link set lo up
sudo ip netns exec client ping -c1 10.20.0.2
```

Start an `iperf3` server in the server ns:

```bash
sudo ip netns exec server iperf3 -s &
```

Baseline throughput (no shaping):

```bash
sudo ip netns exec client iperf3 -c 10.20.0.2 -t 5
```

veth is fast — you'll see multi-Gbps. The point is to compare against the shaped numbers below.

## The exercise — Part 1: shape with HTB

Attach an HTB root qdisc on `c-eth0`, define a single class limited to 10 Mbps with `fq_codel` as the leaf:

```bash
sudo ip netns exec client tc qdisc add dev c-eth0 root handle 1: htb default 10
sudo ip netns exec client tc class add dev c-eth0 parent 1: classid 1:1 htb rate 10mbit ceil 10mbit
sudo ip netns exec client tc class add dev c-eth0 parent 1:1 classid 1:10 htb rate 10mbit ceil 10mbit
sudo ip netns exec client tc qdisc add dev c-eth0 parent 1:10 handle 10: fq_codel
sudo ip netns exec client tc -s qdisc show dev c-eth0
```

Re-run iperf3 — throughput drops to ~10 Mbps. Latency under load (`ping -c 20 10.20.0.2` in parallel with iperf3) stays low because `fq_codel` keeps the queue short.

For contrast, swap the leaf to plain `pfifo` (the classic FIFO, no AQM):

```bash
sudo ip netns exec client tc qdisc replace dev c-eth0 parent 1:10 handle 10: pfifo limit 1000
```

Re-run the same iperf3 + ping. Throughput is the same; latency under load explodes — that's bufferbloat. Swap back to `fq_codel` and watch it go away.

## The exercise — Part 2: classify by DSCP

Add a priority class for DSCP EF (expedited forwarding, marked 46):

```bash
sudo ip netns exec client tc class add dev c-eth0 parent 1:1 classid 1:20 htb rate 5mbit ceil 10mbit prio 1
sudo ip netns exec client tc qdisc add dev c-eth0 parent 1:20 handle 20: fq_codel
sudo ip netns exec client tc filter add dev c-eth0 protocol ip parent 1:0 prio 1 u32 \
    match ip tos 0xb8 0xfc flowid 1:20
```

The `tos 0xb8` matches DSCP 46 (the TOS byte is DSCP shifted left 2 bits). Generate marked and unmarked traffic, observe the marked traffic always wins the bandwidth contest because of `prio 1`.

## The exercise — Part 3: `fq_codel` on a bare interface

The simplest, highest-ROI move on any Linux box doing forwarding: set `fq_codel` as the root qdisc.

```bash
sudo ip netns exec client tc qdisc del dev c-eth0 root
sudo ip netns exec client tc qdisc add dev c-eth0 root fq_codel
sudo ip netns exec client tc -s qdisc show dev c-eth0
```

No classes, no filters. Just AQM doing its job. Most modern distros default to `fq_codel` at boot via the `net.core.default_qdisc` sysctl — check yours with `sysctl net.core.default_qdisc`.

## Verification

- `tc -s qdisc show dev c-eth0` prints byte counts, packet counts, and drops per qdisc.
- `tc -s class show dev c-eth0` prints per-class statistics inside HTB.
- `ping` latency under load distinguishes `fq_codel` (low latency) from plain `pfifo` (bufferbloat).
- `iperf3` confirms shaping is hitting the configured rate.

## Cleanup

```bash
sudo ip netns exec client tc qdisc del dev c-eth0 root 2>/dev/null
sudo pkill iperf3
sudo ip netns del client
sudo ip netns del server
```

## Gotchas

- **Egress only by default.** Ingress shaping needs `tc qdisc add dev X handle ffff: ingress` plus an IFB device, or modern `clsact` qdisc with direct-action filters. Cisco engineers expect `service-policy input` to Just Work; on Linux it's more deliberate.
- **Hardware offloads bypass `tc`.** TSO/GSO can confuse byte accounting and make `htb` ceilings inaccurate. On a host doing real shaping, consider `ethtool -K eth0 tso off gso off` — the trade-off is more CPU per packet for accurate rates.
- **`net.core.default_qdisc`** sets the system-wide default. Set it to `fq_codel` (or `fq` if you're running BBR) in `/etc/sysctl.d/`.
- **The `tos` byte vs DSCP confusion.** The match value in `u32` filters is the full TOS byte; DSCP is the top 6 bits. `0xb8 = 10111000` is DSCP 46 (EF) with the low 2 bits zero.

## Further reading

- [`tc(8)` man page](https://man7.org/linux/man-pages/man8/tc.8.html) — entry point
- [`tc-htb(8)`](https://man7.org/linux/man-pages/man8/tc-htb.8.html) — HTB qdisc reference
- [`tc-fq_codel(8)`](https://man7.org/linux/man-pages/man8/tc-fq_codel.8.html) — `fq_codel` reference
- [Bufferbloat.net `fq_codel` background](https://www.bufferbloat.net/projects/codel/wiki/) — the WHY behind the WHAT
- [LARTC HOWTO](https://lartc.org/howto/) — older but still the most pedagogically clear long-form `tc` guide
