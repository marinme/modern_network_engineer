# Lab A04 — Multicast Routing

Pairs with: [Article 4 — Routing Daemons](../../wiki/article-04-routing-daemons.md) §7

## What this lab teaches

| # | Sub-lab | Topic | Article § |
|---|---------|-------|-----------|
| 1 | [lab-1-pim-sm.md](lab-1-pim-sm.md) | FRR `pimd` PIM-SM — IGMP join, (S,G) entry, mroute table | §7 |
| 2 | [lab-2-smcroute-static.md](lab-2-smcroute-static.md) | `smcroute` — static multicast route without a control plane | §7 |

PIM-Sparse Mode multicast routing on Linux. The Cisco mental model is `ip multicast-routing`, `ip pim sparse-mode` on each interface, and an RP. The Linux equivalent is **FRR's `pimd`**, which speaks PIM-SM (RFC 7761). For the simpler case of forwarding a known (S,G) without a control plane, **`smcroute`** installs static multicast routes — the equivalent of IOS `ip mroute`.

Sub-lab 1 uses pimd with full IGMP signaling. Sub-lab 2 replaces the control plane entirely with a static rule. **Run them separately** — only one process per namespace can hold the multicast forwarding socket.

## Prerequisites

- Article 4 read through §7 (multicast concepts).
- The `netmod/article-04` container running (see below).
- Classic `iperf` (`iperf -s -u -B <group>`) installed in the container — this lab uses multicast streaming, which `iperf3` dropped.

## Container setup

```bash
# From the repo root
docker compose -f containers/article-04/docker-compose.yml run --rm lab
```

Required capabilities (all provided by `--privileged`):

| Capability | Why needed |
|------------|-----------|
| `NET_ADMIN` | Create namespaces, set mc_forwarding sysctl, manage mroute table |
| `SYS_ADMIN` | Mount cgroups, run systemd as PID 1, open raw multicast socket |
| `NET_RAW` | tcpdump, raw multicast sockets for iperf |

Tests are bind-mounted read-only at `/lab/tests/multicast/`.

## Topology

Both sub-labs use the same linear topology:

```
src (10.30.1.10/24) ── r1 (10.30.1.1 / 10.30.2.1) ── dst (10.30.2.10/24)
                        │
                        mc_forwarding=1
                        pimd (sub-lab 1) OR smcroute (sub-lab 2)
```

- `src` — multicast source; runs `iperf -c 239.1.1.1 -u`
- `r1` — router; runs FRR pimd or smcrouted; owns the mroute socket
- `dst` — receiver; runs `iperf -s -u -B 239.1.1.1` (which issues an IGMP join)

## Verification

```bash
./tests/multicast/test.sh 1   # verify FRR pimd PIM-SM
./tests/multicast/test.sh 2   # verify smcroute static mroute
```

Exit `0` all-pass, `1` a check failed, `2` setup error.

## Gotchas

- **`mc_forwarding` is separate from `ip_forward`.** Setting `net.ipv4.ip_forward=1` does not enable multicast forwarding; you must also set `net.ipv4.conf.all.mc_forwarding=1`. They control different code paths in the kernel.
- **One mroute socket per netns.** Only one process can hold the multicast forwarding socket per namespace. Starting both `pimd` and `smcrouted` in the same namespace fails silently — the second one cannot bind. Run sub-labs 1 and 2 in separate topology instances.
- **Classic `iperf`, not `iperf3`.** Multicast support (`-B`, `--ttl`) was removed from `iperf3`. The container ships both; use `iperf` (without the `3`) for this lab.
- **IGMP versions.** The kernel defaults to IGMPv3 with backward compatibility. If a receiver sends IGMPv2 reports and the querier is v3-only, configure `ip igmp version 2` on the FRR interface.
- **No PIM-DM in FRR.** FRR implements PIM-SM (and SSM). PIM Dense Mode requires `mrouted` (deprecated) or a very specific legacy reason.
- **`ip mroute show` requires an active stream.** The (S,G) entry in the kernel mroute table is created when the first packet arrives at the router from the source. Before the stream starts, the table is empty even with pimd running.

## Further reading

- [FRR PIM documentation](https://docs.frrouting.org/en/latest/pim.html)
- [RFC 7761 — PIM-SM](https://datatracker.ietf.org/doc/html/rfc7761)
- [`smcroute(8)`](https://manpages.debian.org/bookworm/smcroute/smcroute.8.en.html)
- [Linux kernel multicast routing](https://www.kernel.org/doc/Documentation/networking/multicast.txt)
- [`ip-mroute(8)`](https://man7.org/linux/man-pages/man8/ip-mroute.8.html)
