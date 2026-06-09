# Lab A04 — VRRP with `keepalived` (and FRR `vrrpd`)

Pairs with: [Article 4 — Routing Daemons](../../wiki/article-04-routing-daemons.md) §5b

## What this lab teaches

| # | Sub-lab | Topic | Article § |
|---|---------|-------|-----------|
| 1 | [lab-1-keepalived.md](lab-1-keepalived.md) | `keepalived` VRRPv3 — election, failover, advertisements | §5b |
| 2 | [lab-2-frr-vrrpd.md](lab-2-frr-vrrpd.md) | FRR built-in `vrrpd` — same semantics, one fewer daemon | §5b |

First-hop redundancy on Linux. The Cisco mental model is HSRP/VRRP/GLBP: two boxes share a virtual IP, one is active, the other takes over when the active fails. On Linux the standard tool is **`keepalived`**, which implements VRRPv2/v3 directly. FRR also ships a `vrrpd` for shops already running FRR. Sub-lab 1 covers keepalived; sub-lab 2 replaces it with FRR's built-in daemon so you can see the configuration difference.

## Prerequisites

- Container-lab experience from Article 2 (namespaces, veth pairs, bridge).
- Article 4 read through §5b (VRRP concepts).
- The `netmod/article-04` container running (see below).

## Container setup

```bash
# From the repo root
docker compose -f containers/article-04/docker-compose.yml run --rm lab
```

Required capabilities (all provided by `--privileged`):

| Capability | Why needed |
|------------|-----------|
| `NET_ADMIN` | Create namespaces, veth pairs, bridge, assign addresses |
| `SYS_ADMIN` | Mount cgroups, run systemd as PID 1 |
| `NET_RAW` | tcpdump, raw VRRP packets |
| `SYS_PTRACE` | pgrep into other PIDs |

Tests are bind-mounted read-only at `/lab/tests/vrrp/`.

## Topology

Both sub-labs use the same three-namespace topology. Build it once at the start of each sub-lab:

```
     r1 (10.10.0.2/24, priority 150)
      │  r1-eth0
      │  r1-br
   [ br0 ] ← LAN bridge namespace
      │  r2-br
      │  r2-eth0
     r2 (10.10.0.3/24, priority 100)

     Virtual IP: 10.10.0.1/24 (MASTER holds it)
```

## Verification

Each sub-lab has an automated checker:

```bash
./tests/vrrp/test.sh 1   # verify keepalived (sub-lab 1)
./tests/vrrp/test.sh 2   # verify FRR vrrpd (sub-lab 2)
```

Exit `0` all-pass, `1` a check failed, `2` setup error.

## Gotchas

- **`net.ipv4.ip_nonlocal_bind`** — the BACKUP can pre-bind the VIP socket before it wins election; set `sysctl -w net.ipv4.ip_nonlocal_bind=1` in the BACKUP namespace if a service binds to the VIP at startup.
- **Preemption** — keepalived preempts by default. To disable, add `nopreempt` in the BACKUP instance block. FRR `vrrpd` follows the same RFC 5798 default.
- **No GLBP equivalent.** For active-active first-hop on Linux, run two VRRP instances with inverted priorities or push balancing to L4 (IPVS/HAProxy).
- **VRRPv3 for sub-second failover.** VRRPv2 advertisement intervals are in whole seconds; v3 uses centiseconds. Set `version 3` (keepalived) or `vrrp 51 version 3` (FRR) and tune the interval.
- **Virtual IP appears as a real IP.** Unlike IOS where the VIP is a phantom, on Linux it is actually assigned to the MASTER's interface and visible in `ip addr show`.
- **One mroute socket conflict.** VRRP advertisements use multicast (`224.0.0.18`); if you are simultaneously running `pimd` or `smcroute`, the multicast socket may conflict. Run VRRP and multicast labs in separate namespace sets.

## Further reading

- [`keepalived` user guide](https://www.keepalived.org/manpage.html)
- [`keepalived.conf(5)`](https://manpages.debian.org/bookworm/keepalived/keepalived.conf.5.en.html)
- [FRR `vrrpd` documentation](https://docs.frrouting.org/en/latest/vrrp.html)
- [RFC 5798 — VRRPv3](https://datatracker.ietf.org/doc/html/rfc5798)
