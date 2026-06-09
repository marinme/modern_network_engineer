---
type: topic
tags: [article-plan, foundation, linux, nftables, systemd-networkd, tuning, ai-callback]
article_number: 5
cluster: Foundation
created: 2026-06-04
updated: 2026-06-04
sources: [[[network-engineer-modernization-series]]]
related: [[[article-01-linux-for-network-engineers]], [[article-02-interfaces-namespaces-topologies]], [[article-03-common-network-admin-tasks]], [[article-04-routing-daemons]], [[systemd-networkd]], [[man-systemd-networkd]], [[legacy-config-coverage-map]]]
status: draft
---

# Article 05 — Production Linux Network Appliance

Last of five Linux foundation articles. The reader can now translate, build topologies, do common admin tasks, and stand up routing protocols. This article covers everything *else* a Linux box needs to behave like a hardened production network appliance: **persistence across reboots, `nftables` in depth, kernel and NIC tuning, QoS, and a structured troubleshooting workflow.**

One thesis: **the operational hygiene that makes the difference between a Linux box that forwards packets and a Linux box you would stake an SLA on.**

Everything from [[article-12-containerlab]] onward leans on the persistence and tuning patterns established here, and the closing legacy-coverage page ([[legacy-config-coverage-map]]) cross-references this article more than any other.

## Expected outcome

The reader finishes able to:

- Declare a non-trivial network configuration (multiple interfaces, a bond, a VLAN, a firewall) entirely through configuration files and verify it survives a reboot.
- Write `nftables` rule sets that exercise hooks, sets, maps, and NAT chains, and reason about chain priority order.
- Name and use the dozen sysctls a network engineer should know cold, pairing each knob with the counter that diagnoses its symptom.
- Toggle NIC offloads with `ethtool` and measure the data-plane effect.
- Pin NIC IRQ affinity and confirm load distribution across CPUs under synthetic load.
- Configure `tc` with HTB shaping and `fq_codel` queueing as a baseline QoS posture.
- Run a structured troubleshooting workflow against a misbehaving Linux router and identify root cause from kernel-side counters and ring-buffer messages.
- Use an LLM to generate `nftables` rule sets from intent, and verify the result against `nft list ruleset` and a synthetic traffic load.

## Outline

1. **Persistence: declared network state.** Where boot-time network configuration lives. [[systemd-networkd]] (`/etc/systemd/network/*.network`, `.netdev`, `.link`) — the modern default; the concept page maps Cisco's `startup-config` / `running-config` model onto Linux. **Netplan** (Ubuntu) — YAML wrapper that generates `systemd-networkd` config under the hood; the two-layer relationship is non-obvious until you have hit it. **NetworkManager** (RHEL/desktop) — `nmcli` CLI, different daemon, different file location. The "which daemon owns this interface" diagnostic (`networkctl status`, `nmcli device status`). This section is **the answer to the persistence promise made in [[article-01-linux-for-network-engineers]]**: every `ip` and `nft` command takes effect immediately and disappears at reboot; this is where the reader learns how to make it stick.
2. **Persisting `nftables`.** `nftables.service` and `/etc/nftables.conf`. Atomic ruleset loading via `nft -f`. Syntax-validation at load time (the safety guarantee — bad rulesets refuse to load rather than partially apply). The reload workflow during change windows. How frontends (`firewalld`, `ufw`) persist their state and what they actually write to disk.
3. **`nftables` in depth.** Tables, chains, families (`ip`, `ip6`, `inet`, `arp`, `bridge`, `netdev`). Hook points (`prerouting`, `input`, `forward`, `output`, `postrouting`) and priorities — including the priority-ordering trap where a filter chain at priority 0 vs a NAT chain at priority -100 vs +100 produces different evaluation orders and silently breaks behavior. Sets and maps for fast lookups against large match lists. NAT chains (`type nat hook postrouting`) and the SNAT/DNAT/MASQUERADE distinction. Conntrack zones for the edge case where one box NATs the same traffic twice. The mental model that survives reading any rule set in the wild.
4. **Sysctls a network engineer should know cold.** The dozen that matter, each paired with the symptom it causes when wrong: `net.ipv4.ip_forward` (forwarding silently stops), `net.ipv6.conf.all.forwarding` (same, IPv6), `net.ipv4.conf.<iface>.rp_filter` (asymmetric-path drops in strict mode), `net.ipv4.conf.all.accept_redirects` (security implications), `net.ipv4.tcp_rmem` / `tcp_wmem` (window-scaling failures at high BDP), `net.core.somaxconn` (listen-queue overflow), `net.core.netdev_max_backlog` (packet drops under burst), `net.ipv4.neigh.default.gc_thresh{1,2,3}` (ARP table overflow on a large L2). The reader walks away with a knob-to-counter mapping that survives the post-mortem.
5. **NIC offloads with `ethtool`.** `-k` to list, `-K` to set: TSO, GSO, GRO, LRO, RSS. When to turn them on (most cases), when to turn them off (capture / debug / virtualization edge cases). The interaction with `tcpdump` capture that confuses everyone the first time — GRO-coalesced super-packets show up in `tcpdump` as single oversized frames that the wire never carried.
6. **IRQ affinity and softirqs.** `/proc/interrupts`, `set_irq_affinity`, RPS, RFS. Why a single-CPU bottleneck happens on a busy box. The multi-queue NIC model (RSS) and how to confirm queues are distributed across cores. Cross-reference to §7's `tc` qdisc treatment for the case where the bottleneck is the queueing discipline, not the CPU.
7. **QoS: classification, shaping, and queueing with `tc`.** Linux's MQC analog is `tc` building a tree of qdiscs (queueing disciplines), classes (bandwidth allocations), and filters (classification rules). Two qdiscs cover almost everything: **HTB** for hierarchical shaping (the `shape average` / `bandwidth percent` analog) and **`fq_codel`** as the modern default queueing discipline (the WRED-that-actually-works without tuning). One paragraph on the tree model, one paragraph on DSCP-byte semantics under `u32` filters, one paragraph on the egress-default / ingress-via-IFB asymmetry that bites Cisco engineers when they expect `service-policy input` to Just Work. Set `net.core.default_qdisc=fq_codel` system-wide and most boxes are 80% of the way to a healthy QoS posture. Full exercise in **[Lab A05 — QoS](../labs/lab-a05-qos/)**.
8. **Troubleshooting workflow.** A structured diagnostic walk in order, not a list of commands in isolation: `ip -s -s link` for interface drops → `ss -s` for socket summary → `nstat -a` for protocol counter deltas → `dropwatch -l kas` for kernel-side drop reasons → `dmesg | grep -i <iface>` for NIC events → `ethtool -S <iface>` for NIC-internal counters. Plus **`ip monitor`** as the live-events companion: run it in a second window when something is changing and you want to watch links flap, routes get re-installed by a daemon, or neighbors transition states in real time. Filterable by object (`ip monitor link`, `ip monitor route`, `ip monitor neigh`) and pipe-friendly. The embedded lab exercises this workflow under seeded faults so the reader has muscle memory by the end.
9. **How LLM agents fit here.** Second generative use case in the series, parallel to Article 4's FRR generation. `nftables` is the natural domain: verbose syntax, common patterns (set-membership-based ACLs, multi-stage NAT, log-and-count), well-documented online, easy to verify against `nft list ruleset` and a traffic generator. The agent's right job is intent-to-ruleset; the reader's job is verification with `nft -c` (syntax check at the file level) and a synthetic load (behavioral check). Same paste/run/verify loop as Article 4, applied to a new domain. Still no agent tool use — the pattern remains paste/run/verify until [[article-12-containerlab]].

## Lab

**Embedded lab — [Lab A05 — Production Appliance](../labs/lab-a05-appliance/).** Nine chained sections against a single Linux container running `systemd`, with "reboot" simulated via `docker restart`:

1. Declare network state with `systemd-networkd` (§1)
2. Declare firewall state with `/etc/nftables.conf` (§2)
3. `nftables` in depth — hooks (§3)
4. `nftables` in depth — sets and maps (§3)
5. `nftables` in depth — NAT chains (§3)
6. Sysctl knobs and their symptoms (§4)
7. NIC offloads under `iperf3` load (§5)
8. IRQ affinity and CPU distribution (§6)
9. Troubleshooting workflow under seeded faults (§8)

**Standalone companion lab:**

- [Lab A05 — QoS](../labs/lab-a05-qos/) — pairs with §7. `tc` with HTB and `fq_codel` against a `netem`-rate-limited link. Standalone because QoS demonstrations need controlled bandwidth and live latency measurement during contention — neither fits cleanly as a section in the chained appliance lab.

## Foundational material needed

| Prerequisite | Covered where | Notes |
|---|---|---|
| `ip` suite, namespaces, interface types | [[article-01-linux-for-network-engineers]], [[article-02-interfaces-namespaces-topologies]] | Direct prerequisite |
| Basic `nftables` (table → chain → rule, hooks) | [[article-01-linux-for-network-engineers]] §nftables, [[article-03-common-network-admin-tasks]] | Direct prerequisite |
| Routing daemons fluency | [[article-04-routing-daemons]] | Useful but not strict — most of this article is daemon-agnostic |
| Linux kernel as a forwarder | [[article-01-linux-for-network-engineers]], [[article-04-routing-daemons]] | The data-plane perspective the tuning sections lean on |

## Assumed networking knowledge

External prerequisites the reader brings in. See [[assumed-networking-knowledge]].

- Stateful firewalling, NAT semantics, connection tracking (framing for §3)
- Hardware vs software forwarding distinction (NIC offloads make sense only with this)
- TCP congestion control basics (so the `tcp_rmem` / `tcp_wmem` discussion in §4 lands)
- QoS as a category: classification, marking (DSCP), shaping vs policing, AQM, bufferbloat (the WHY behind `fq_codel`)
- Symptoms-to-causes mental model for network failures (the troubleshooting section assumes the reader knows what "asymmetric routing" looks like in a packet capture; it teaches the Linux-side diagnosis, not the protocol cause)

## How LLM agents fit here

Second generative use case in the series, parallel to Article 4's FRR generation. `nftables` rule sets are tedious to write from scratch, follow common patterns, and are easy to verify against `nft list ruleset` and a traffic generator. The agent's right job is intent-to-ruleset.

The verification habit is the same as Article 4 — paste, syntax-check (`nft -c -f`), shape-check (`nft list ruleset`), behavior-check (synthetic traffic) — applied to a new domain. The pattern compounds across articles: by the time the reader reaches Article 11 (Containerlab) and tool-using agents enter the picture, the paste/run/verify reflex is muscle memory.

Sets and maps especially benefit from agent generation because the syntax is verbose and the patterns are common. The reader's intent ("permit these subnets to these ports, NAT outbound through this interface, log anything that hits the default-drop, rate-limit ICMP to 10 per second") becomes a rule set the reader could not have produced in five minutes by hand.

## Commitments tracked from earlier articles

- **Persistence**, promised in [[article-01-linux-for-network-engineers]]. The Article 1 translation table shows `write memory` mapping to "edit `/etc/systemd/network/*.network` or `netplan apply`," and the gotchas list says: "Persistence is a separate concern (you write files for that, see Article 4); the running state is whatever the kernel currently believes." After the Article 4 split, the forward-pointer now resolves here. This article's **§1–§2** plus the embedded lab's sections 1–2 together discharge the promise. The lab must show the reader (a) configuring two interfaces, a bond, a VLAN, and an `nftables` ruleset via `systemd-networkd` + `/etc/nftables.conf`, (b) restarting the container (the "reboot"), and (c) confirming everything came back exactly as declared.
- **`nftables` depth** promised in [[article-01-linux-for-network-engineers]]. Article 1's nftables section is recognition-only and forward-points to "Article 4 for depth"; after the split, the depth treatment lives here in §3 plus the embedded lab's sections 3–5. Discharge requires the hooks-priority trap, sets, maps, and NAT chains all to be demonstrated with the reader's hands.

When this article is drafted, the two commitments above should each be cross-linked back to their origin in Article 1, and Article 1's forward-pointers should be updated from "Article 4" to point here.

## Open questions

- **Container vs VM for the embedded lab.** Persistence-across-reboot is the lab's centerpiece, which argues for a VM. But the rest of the series uses containers and reader friction matters. Probably a privileged container with `systemd` inside (e.g., `jrei/systemd-debian:12`), where "reboot" is a `docker restart` that exercises the same persistence paths. Worth confirming when the lab is built that all the relevant `systemd` units (networkd, nftables.service) come up cleanly on container restart.
- **Distribution standardization.** The persistence story diverges sharply between Ubuntu (Netplan / `systemd-networkd`) and RHEL-family (NetworkManager). Standardize on Debian/Ubuntu with networkd for the lab to match [[article-12-containerlab]] defaults, but the article body must name both daemons explicitly because RHEL-shop readers will see NetworkManager on the boxes they SSH into at work.
- **Should QoS move into the embedded lab as a tenth section?** The QoS lab needs `netem` and a constrained link; that infrastructure is hard to share with the other sections. Keeping QoS standalone is the easier ship and the existing companion-lab pattern.
