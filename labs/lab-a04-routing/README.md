# Lab A04 — Routing (Linux as a Router)

Pairs with: [Article 4 — Routing Daemons](../../wiki/article-04-routing-daemons.md)

## What this lab teaches

Seven chained sub-labs against a single three-namespace topology (`r1 — r2 — r3`). Build the topology once with `/lab/setup.sh`, then work through each section; the topology persists across all of them. VRRP and multicast each have their own companion lab because their topologies and failure modes differ.

| # | Sub-lab | Topic | Builds | Verifies |
|---|---------|-------|--------|---------|
| 1 | [lab-1-rib-vs-fib](./lab-1-rib-vs-fib.md) | RIB vs FIB — two queries, two data stores | vtysh primer | FRR sockets ready; RIB and FIB both queryable; connected routes consistent |
| 2 | [lab-2-ospf](./lab-2-ospf.md) | First OSPF adjacency | OSPF between r1↔r2↔r3 | Neighbor Full; loopback as `proto ospf` in FIB; ping reachability |
| 3 | [lab-3-bgp](./lab-3-bgp.md) | First BGP session (numbered eBGP) | eBGP over loopbacks | Session Established; prefix as `proto bgp` in FIB |
| 4 | [lab-4-bgp-unnumbered](./lab-4-bgp-unnumbered.md) | BGP unnumbered | Interface-based eBGP over IPv6 link-local | Established session; fe80:: next-hop; IPv4 prefix in FIB |
| 5 | [lab-5-bfd](./lab-5-bfd.md) | BFD-accelerated failover | BFD wired to BGP/OSPF | BFD peer Up; ≤300ms TX interval; routing session references BFD |
| 6 | [lab-6-persistence](./lab-6-persistence.md) | Persisting FRR config | `write` / config-file management | frr.conf non-empty; router stanza present; running matches on-disk |
| 7 | [lab-7-journal-correlation](./lab-7-journal-correlation.md) | Journal correlation | Three-shell flap exercise | frr@* units in journal; kernel entries present; jq cross-writer query works |

## Prerequisites

- Docker installed. `docker compose` available.
- Familiarity with namespaces from [Article 2](../../wiki/article-02-interfaces-namespaces-topologies.md).
- No prior FRR experience required. Skimming the [FRR documentation index](https://docs.frrouting.org/) once before starting will help — the lab uses `vtysh` throughout.
- About 90–120 minutes the first time. Individual sections are fast once the topology is up.

## The setup

Container source: [`containers/article-04/`](../../containers/article-04/)

This container runs **systemd as PID 1** so that per-namespace FRR template units and `journalctl` work as the article describes. The container requires `--privileged` for cgroup management.

```bash
docker compose -f containers/article-04/docker-compose.yml run --rm lab
```

Inside the container, build the `r1—r2—r3` topology:

```bash
/lab/setup.sh                      # creates namespaces, veth pairs, starts frr@r1/r2/r3
ip netns list                       # confirm: r1  r2  r3
systemctl status 'frr@*'            # all three should be active (running)
```

Capabilities used:

| Flag | Why |
|------|-----|
| `--privileged` | systemd PID 1 needs cgroup v2 management and mount operations |
| (includes) `NET_ADMIN` | ip / nft / tc / bridge — configure namespaces and interfaces |
| (includes) `NET_RAW` | tcpdump / ping raw sockets |
| (includes) `SYS_ADMIN` | ip netns add bind-mounts; FRR systemd units |

### Connecting to FRR in a namespace

```bash
/lab/frrvtysh r1                   # interactive vtysh for r1
/lab/frrvtysh r1 -c 'show ip route'  # non-interactive one-shot
ip netns exec r1 vtysh -N r1       # equivalent long form
```

FRR uses separate socket paths per namespace (`/run/frr/r1/`, `/run/frr/r2/`, `/run/frr/r3/`) via `--pathspace`. The `-N r1` flag tells vtysh which pathspace to connect to.

### Topology

```
10.0.0.1/32 (lo)       10.0.0.2/32 (lo)       10.0.0.3/32 (lo)
┌─────────┐            ┌─────────┐            ┌─────────┐
│   r1    │──10.0.12.x─│   r2    │──10.0.23.x─│   r3    │
└─────────┘            └─────────┘            └─────────┘
r1: 10.0.12.1/24      r2: 10.0.12.2/24        r3: 10.0.23.2/24
                           10.0.23.1/24
```

## Verification

Tests are mounted read-only at `/lab/tests/routing/`. Run from `/lab`:

```bash
./tests/routing/test.sh            # list available sub-labs
./tests/routing/test.sh 1          # RIB vs FIB
./tests/routing/test.sh 2          # OSPF adjacency
./tests/routing/test.sh 3          # BGP session
./tests/routing/test.sh 4          # BGP unnumbered
./tests/routing/test.sh 5          # BFD
./tests/routing/test.sh 6          # Persistence
./tests/routing/test.sh 7          # Journal correlation
```

Exit `0` = all checks passed. Exit `1` = a check failed. Exit `2` = setup error.

## A note on the chained structure

These seven sub-labs build on each other. Lab 2 (OSPF) is the underlay for Lab 3 (BGP over loopbacks). Lab 4 replaces Lab 3's numbered session with unnumbered. Lab 5 adds BFD to whichever session is Established. Lab 6 saves what you built. Lab 7 reads the journal from the live topology. You can run them in order or jump to any section — the topology persists as long as the container is running.

## Cleanup

```bash
exit          # exits the shell
              # docker compose ... run --rm removes the container automatically
              # all namespaces and veths live inside the container and disappear with it
```

To reset the topology without exiting the container:

```bash
/lab/setup.sh teardown
/lab/setup.sh
```

## Further reading

- [FRR Documentation](https://docs.frrouting.org/) — the canonical reference
- [FRR `vtysh` documentation](https://docs.frrouting.org/en/latest/vtysh.html)
- [Cumulus Linux BGP Unnumbered](https://docs.nvidia.com/networking-ethernet-software/cumulus-linux/Layer-3/Border-Gateway-Protocol-BGP/) — the convention's origin
- [FRR `bfdd` documentation](https://docs.frrouting.org/en/latest/bfd.html)
- [`journalctl(1)`](https://man7.org/linux/man-pages/man1/journalctl.1.html)
- [Lab A04 — VRRP](../lab-a04-vrrp/) — companion lab for §5b
- [Lab A04 — Multicast](../lab-a04-multicast/) — companion lab for §7
