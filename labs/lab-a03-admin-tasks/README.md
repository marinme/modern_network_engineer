# Lab A03 — Common Network-Admin Tasks in Base Linux

Pairs with: [Article 3 — Common Network-Admin Tasks, Done in Base Linux](../../wiki/article-03-common-network-admin-tasks.md)

Article 1 translated `ip` commands; Article 2 built topology from namespaces and interfaces. This lab puts that foundation to work on the twenty-one tasks a network engineer actually does in a normal month: static routes with failover, stateful ACLs, VLAN trunks, bonding, NAT, DHCP, VRFs, proxy ARP, PMTU discovery, NTP, syslog forwarding, LLDP, and a full appliance that chains them all together.

Twelve sub-labs, one container, all verify-only tests.

## What this lab teaches

| Lab | Topic | Builds | Verifies |
|-----|-------|--------|---------|
| [Lab 1](./lab-1-routing-failover.md) | Routing & Failover | ECMP multipath + metric backup routes | `ip route get` selects the right path |
| [Lab 2](./lab-2-acl-stateful.md) | Stateful ACL + Capture | nft forward chain, `ct state`, per-host tcpdump | Allowed port connects; blocked port refused; ruleset has the ct rule |
| [Lab 3](./lab-3-vlan-trunk.md) | VLAN Trunk | Two VLAN-aware bridges with trunk veth | Same-VLAN hosts reach across trunk; cross-VLAN isolated; distinct 802.1Q tags visible |
| [Lab 4](./lab-4-bonding.md) | Bonding | active-backup bond + 802.3ad LACP bond | `/proc/net/bonding` shows mode + active slave; LACP partner negotiated |
| [Lab 5](./lab-5-nat-pat.md) | NAT / DNAT | Masquerade outbound + DNAT port-forward | nft ruleset has masquerade + dnat; `conntrack -L` shows tuples |
| [Lab 6](./lab-6-mirror-span.md) | Port Mirror / SPAN | `tc clsact` + `mirred` to a dummy monitor | `tc filter` has mirred action; `tcpdump` on monitor sees copies |
| [Lab 7](./lab-7-dhcp.md) | DHCP Server + Relay | `dnsmasq` pool + `dhcrelay` across subnets | Lease file has client MAC; relayed client on remote subnet |
| [Lab 8](./lab-8-vrf-rpf.md) | VRF + rp_filter | Two VRFs with isolated tables + asymmetric rp_filter | In-VRF reachability; cross-VRF isolation; rp_filter drop confirmed via `nstat` |
| [Lab 9](./lab-9-arp-proxyarp.md) | ARP + Proxy ARP | PERMANENT neigh entry + proxy_arp sysctl | Neigh state PERMANENT; host ARPs resolve off-subnet target to router MAC |
| [Lab 10](./lab-10-mtu-pmtu.md) | MTU + PMTU | Constrained-MTU link; DF-bit ping probes | `ip link` MTUs match; large-DF fails; small-DF succeeds; PMTU cached |
| [Lab 11](./lab-11-services.md) | NTP + Syslog + LLDP | `chrony` local-stratum NTP; `rsyslog` TCP forward; per-ns `lldpd` | Chrony selects source; syslog token arrives; LLDP neighbor discovered bidirectionally |
| [Lab 12](./lab-12-appliance.md) | Full Appliance | wan–r–lan with NAT+DNAT+ACL+DHCP+iperf3 | All flows working; counters increment; conntrack populated |

## Prerequisites

- Docker installed and running.
- Comfortable reading `ip -br link`, `ip route`, `ip netns list` output (Article 1 comfort).
- Completed or read Articles 1 and 2 — this lab uses namespaces and interface types without re-teaching them.
- The host kernel must have these modules available (loaded by the labs): `bonding`, `dummy`, `8021q`, `act_mirred`, `cls_matchall`, `sch_clsact`. Check with `lsmod | grep -E 'bonding|dummy|8021q|act_mirred|matchall|sch_clsact'`; if missing, `modprobe <name>` from the host.
- About three to four hours for all twelve sub-labs on a first pass.

## The setup

Build and enter the container from the repo root:

```bash
# Option A: docker compose (recommended — handles caps automatically)
docker compose -f containers/article-03/docker-compose.yml run --rm lab

# Option B: docker run
docker build -t netmod/article-03 containers/article-03/
docker run -it --rm \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  --cap-add=SYS_ADMIN \
  --security-opt apparmor=unconfined \
  --name article-03 \
  netmod/article-03
```

You land at `root@workbench:/lab#`. The `tests/` directory is mounted read-only from the repo so you can run `./tests/test.sh N` as you complete each lab.

**Capability flags:**

| Flag | Why |
|------|-----|
| `NET_ADMIN` | `ip netns`, `ip link`, `ip route`, `nft`, `tc`, `bridge` |
| `NET_RAW` | `tcpdump`, `ping` raw socket |
| `SYS_ADMIN` | Remount `/proc/sys` rw for per-namespace `sysctl -w` |
| `apparmor=unconfined` | Required on Ubuntu/Debian hosts |

## A note on persistence

All namespace state (interfaces, routes, nft rules, sysctl values, DHCP leases) lives in kernel memory inside the container. It vanishes when the container exits. Starting fresh is `exit` → re-run the container. Article 5 covers making configurations survive reboots with `systemd-networkd` and `nft -f`.

## Cleanup (inside the container)

Each sub-lab ends with `ip netns del <name>` for each namespace you created. Deleting a namespace tears down everything inside it — interfaces, routes, nft rules — including the namespace-side of each veth pair (the other end is garbage-collected).

```bash
# Generic cleanup after any sub-lab:
ip netns list                       # see what's running
ip netns del h1 r h2 wan lan srv    # whatever names you used
```

If you want to reset between sub-labs without exiting the container:

```bash
for ns in $(ip netns list | awk '{print $1}'); do ip netns del "$ns"; done
```

## Further reading

- `man 8 ip-route`, `man 8 ip-rule`, `man 8 ip-netns`
- `man 8 nft` — the full nftables reference
- `man 8 tc`, `man 8 tc-mirred` — traffic-control framework
- `man 8 dhcrelay` — DHCP relay agent
- `man 5 dnsmasq` — dnsmasq config reference
- `man 1 chronyc`, `man 5 chrony.conf`
- `man 8 rsyslogd`, the rsyslog.conf(5) format
- `man 8 lldpd`, `man 8 lldpcli`
- Linux kernel docs `Documentation/networking/bonding.rst`
- Linux VRF documentation: `ip-link(8)` type vrf section, and [https://www.kernel.org/doc/html/latest/networking/vrf.html](https://www.kernel.org/doc/html/latest/networking/vrf.html)
