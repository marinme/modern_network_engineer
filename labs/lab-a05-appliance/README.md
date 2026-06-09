# Lab A05 — Production Linux Network Appliance

Pairs with: [Article 5 — Production Linux Network Appliance](../../wiki/article-05-production-appliance.md)

## What this lab teaches

A chained walk-through that takes a single Linux box from "default install" to "production-ready network appliance": declared network configuration via `systemd-networkd`, declared firewall via `/etc/nftables.conf`, `nftables` in depth (hooks, sets, maps, NAT), the sysctl knobs that matter, NIC offload control with `ethtool`, IRQ affinity with multi-queue NICs, and a troubleshooting workflow exercised under seeded faults.

The lab exercises every section of the article that is not flagged as recognition-only. **QoS** gets its own standalone companion lab because the demonstrations need a `netem`-rate-limited link and live latency measurement during contention — neither fits cleanly as a section in the chained lab.

## Prerequisites

- Docker, with privileges to run a `systemd`-enabled container.
- Familiarity with Article 1's `ip`-suite material, Article 3's basic `nftables` material, and Article 4's FRR fluency (the troubleshooting section uses a routing daemon as one of the seeded faults).
- About 90–120 minutes the first time.

## The setup

Container source: [`containers/article-05/`](../../containers/article-05/). A `systemd`-enabled image (`jrei/systemd-debian:12` base) with `iproute2`, `nftables`, `ethtool`, `iperf3`, `dropwatch`, `mpstat` (`sysstat`), `conntrack`, and `frr` preinstalled. The container's "reboot" is `docker restart article-05` from the host — `systemd` brings the box back up, `systemd-networkd` reapplies its configuration, and `nftables.service` reloads its ruleset, exactly as a real box would.

```bash
docker build -t netmod/article-05 containers/article-05
docker run -d \
  --privileged \
  --name article-05 \
  --tmpfs /tmp --tmpfs /run \
  netmod/article-05
docker exec -it article-05 bash
```

> **Why `--privileged`.** The lab toggles sysctls, pins IRQ affinity, and runs `systemd` as PID 1, which need capabilities beyond `--cap-add=NET_ADMIN`. The container does not need access to the host's network namespace; the privilege scope is the container's own kernel-visible knobs.

## The exercise

### 1. Declare network state with `systemd-networkd`

The reader writes `.network`, `.netdev`, and `.link` files in `/etc/systemd/network/` to declare a static address on one interface, a bond across two others, and a VLAN on the bond. Reloads with `networkctl reload`, verifies with `networkctl status`. Then exits the shell, runs `docker restart article-05` from the host, re-enters, and confirms everything came back identically. This is the persistence story Article 1 promised, finally landed.

### 2. Declare firewall state with `/etc/nftables.conf`

The reader writes a minimal ruleset (Article 1's default-drop input chain plus a forward chain) to `/etc/nftables.conf`, enables `nftables.service` (`systemctl enable --now nftables`), restarts the container, and confirms the ruleset is in place. Then breaks the file (syntax error), restarts, and watches `nftables.service` fail loudly — the configuration is validated at load time, which is the safety guarantee a router-shop reader needs to see explicitly to trust the model.

### 3. `nftables` in depth — hooks

The reader extends the ruleset to add chains attached to `prerouting`, `forward`, and `postrouting`, each with a different priority. Inserts a `log prefix "HOOK-<name> "` rule at the top of each. Sends a single packet through the box (`curl http://example.com`) and reads `dmesg` to trace the packet's journey through the hooks in priority order. The mental model the article promises lands here, with the priority numbers in front of you on the screen.

### 4. `nftables` in depth — sets and maps

Convert a flat list of permit rules into a single rule referencing a named `set { ... }`. Add and remove set members at runtime with `nft add element` / `nft delete element` and watch firewall behavior change with no reload — the runtime-mutability point. Then build a destination-NAT map keyed by inbound VLAN interface that DNATs to different backends per VLAN. Demonstrates why sets/maps are not optional once a real production ruleset crosses a few hundred lines.

### 5. `nftables` in depth — NAT chains

Write a `type nat hook postrouting` chain that SNATs traffic leaving one interface, and a `type nat hook prerouting` chain that DNATs traffic arriving on another. Verify with `conntrack -L` that the kernel tracked the translations. Demonstrate the priority-ordering trap: a filter chain at priority 0 vs a NAT chain at priority -100 vs +100 produces different rule-evaluation orders, and the wrong order silently breaks behavior. This is the section that earns the article's "the surprise is always in the model" sentence.

### 6. Sysctl knobs and their symptoms

For each of the eight or nine sysctls the article names: read the current value (`sysctl <key>`), induce the symptom by setting it to a known-bad value, observe the failure mode, restore. Most informative cases: `net.ipv4.ip_forward=0` (forwarding silently stops, no error), `net.ipv4.conf.all.rp_filter=1` (asymmetric routing drops appear in `nstat` as `IpInAddrErrors`), `net.ipv4.neigh.default.gc_thresh3=128` (neighbor table overflows on a synthetic scan), `net.core.netdev_max_backlog` (drops show up in `/proc/net/softnet_stat` under burst). The reader pairs each knob with the counter that diagnoses it — that pairing is the lab's deliverable.

### 7. NIC offloads under `iperf3` load

Start `iperf3 -s` in one shell, `iperf3 -c localhost -t 30` in another, watch `ip -s -s link show dev <iface>` and `ethtool -S <iface>` evolve. Toggle GRO and TSO off with `ethtool -K`; observe both throughput and per-packet size statistics change. (`veth` shows this less dramatically than a real NIC but the shape is the same — the section flags this honestly so the reader knows the magnitude they would see on bare metal.) Restore. The reader sees one concrete reason a `tcpdump` from a real NIC may show packet sizes the wire never carried.

### 8. IRQ affinity and CPU distribution

`cat /proc/interrupts` to identify the relevant interrupt lines, observe their CPU distribution under the §7 load using `mpstat -P ALL 1`. Pin everything to a single CPU; rerun the load test; observe `mpstat` going single-CPU-saturated. Distribute back to all CPUs, observe even loading. The lesson: a busy box pinning everything to CPU0 by default is a real production failure mode, and the diagnosis takes thirty seconds once you know to look. (`veth` doesn't expose RSS/MSI-X the way a real NIC does, so this section explains how to read `/proc/interrupts` on a real box at the end.)

### 9. Troubleshooting workflow under seeded faults

A script at `/lab/seed-fault.sh <n>` introduces one of six faults without telling the reader which: MTU mismatch on a path, `rp_filter=1` strict-mode drop, full conntrack table, runaway interface error counters, missing route, wrong sysctl on forwarding. The reader walks the article's documented diagnostic order — `ip -s -s link` → `ss -s` → `nstat -a` → `dropwatch -l kas` → `dmesg | tail -50` → `ethtool -S` — until they identify the symptom and the root cause. Then `/lab/clear-fault.sh` reverts, and they try the next seed. By the end of six seeds the diagnostic order is muscle memory, which is the actual deliverable of the article.

## Verification

You've done the lab successfully if you can:

- Declare a non-trivial network configuration in `.network` files and survive a container restart with no manual reapplication.
- Read an `nftables` ruleset with hooks, sets, maps, and NAT chains and trace a packet through it without looking up syntax.
- Name the sysctl that diagnoses each of: forwarding silently broken, asymmetric routing drops, neighbor table overflow, packet backlog drops.
- Use `nstat -a` to see protocol counter deltas across a synthetic load.
- Walk the structured troubleshooting workflow against an unknown fault without prompting and arrive at the root cause inside ten minutes.

## Cleanup

```bash
docker stop article-05 && docker rm article-05
```

Persistence in the lab is intentional (sections 1–2 depend on it surviving a `docker restart`), so the cleanup is manual rather than `--rm`-driven. Once the container is removed, nothing persists.

## Further reading

- [`systemd.network(5)`](https://www.freedesktop.org/software/systemd/man/latest/systemd.network.html), [`systemd.netdev(5)`](https://www.freedesktop.org/software/systemd/man/latest/systemd.netdev.html), [`systemd.link(5)`](https://www.freedesktop.org/software/systemd/man/latest/systemd.link.html) — the unit file syntax
- [nftables wiki](https://wiki.nftables.org/) — the canonical reference
- [`sysctl(8)`](https://man7.org/linux/man-pages/man8/sysctl.8.html), [`tcp(7)`](https://man7.org/linux/man-pages/man7/tcp.7.html) — the knobs the article names
- [`ethtool(8)`](https://man7.org/linux/man-pages/man8/ethtool.8.html), [`dropwatch(1)`](https://github.com/nhorman/dropwatch) — NIC and kernel-drop diagnostics
- [`nstat(8)`](https://man7.org/linux/man-pages/man8/nstat.8.html) — protocol counter deltas
- [`conntrack(8)`](https://manpages.debian.org/conntrack-tools/conntrack.8.en.html) — the NAT verification companion in §5
