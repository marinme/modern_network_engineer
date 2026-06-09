# Labs — Network Engineer Modernization Series

Hands-on labs for the series. Each lab is a self-contained exercise paired with one or more wiki articles. Articles are for *reading* (concept, model, gotchas); labs are for *doing* (commands, verification, screenshots, working artifacts).

## Why the split

Each wiki article in [`../wiki/`](../wiki/) names the tools, explains the mental model, and points to the lab that exercises it. The lab is where the reader types commands, observes output, and produces a working artifact. Keeping the two separate means:

- Articles stay readable end to end without scrolling past 300 lines of command output.
- Labs can be updated (new screenshots, new container versions) without re-editing the conceptual narrative.
- Labs can be reused across articles when the same exercise illustrates two topics.
- The reader can skim the article on a phone and run the lab on a laptop.

## Convention

```
labs/
  README.md                       This file. Conventions + index.
  lab-aNN-topic/                  One directory per lab.
    README.md                     The lab walkthrough — the reader's entrypoint.
    Dockerfile, *.yml, configs/   Runnable artifacts when the lab ships them.
    tests/                        Automated verification (see "Verifying a lab").
      test.sh                     Standard entrypoint; multi-part labs take a part arg.
    assets/                       Screenshots and images for this lab.
```

Naming: `lab-a<article-number>-<topic-slug>/`. Two-digit zero-padded article number, kebab-case topic. Examples: `lab-a01-translation`, `lab-a04-vrrp`, `lab-a05-qos`, `lab-a04-multicast`. When a lab pairs with multiple articles, name it after the article that owns the concept and cross-reference from the others.

Each lab's `README.md` follows a standard shape:

1. **What this lab teaches** — one paragraph naming the article it pairs with and the specific concept it exercises.
2. **Prerequisites** — what the reader needs installed and which prior labs (if any) they should have done.
3. **The setup** — how to bring up the environment (container, namespace topology, etc.). Minimum command surface.
4. **The exercise** — step-by-step with expected output. Screenshots embedded inline where they add information.
5. **Verification** — how the reader knows the lab worked. When the lab has a runnable topology, this is backed by an automated checker at `tests/test.sh` (see [Verifying a lab](#verifying-a-lab)).
6. **Cleanup** — how to tear down without leaving state on the host.
7. **Further reading** — upstream docs, man pages, RFCs.

The lab `README.md` is plain Markdown — no Obsidian frontmatter. Articles are the wiki; labs are operational artifacts. Cross-links from articles to labs use repo-relative paths (`../labs/lab-a04-vrrp/`); cross-links from labs back to articles use the same shape (`../wiki/article-04-routing-daemons.md`).

## Verifying a lab

Every lab that builds a runnable topology ships an automated checker at **`tests/test.sh`** —
the standard, recurring way to confirm a finished lab actually works. Run it from inside the
lab's container after you've built the topology:

```bash
./tests/test.sh            # single-part lab
./tests/test.sh <part>     # multi-part lab: sub-labs sharing one container (e.g. 1, 4-svi)
```

`test.sh` lists its parts when run with no argument. Exit status is `0` (all checks passed),
`1` (a check failed), or `2` (setup error / unknown part).

The checkers follow three rules:

- **Verify-only and non-destructive.** They only read live state, send pings, and sniff
  passively (`tcpdump`). They never create, delete, or reconfigure a namespace, address,
  route, or sysctl — safe to run against what you built by hand, and safe to re-run.
- **Auto-discovery, not hard-coded names.** They discover the namespaces and IPs you
  actually used from the live kernel state and identify roles by topology shape, so they
  pass even if you renamed things or chose different subnets.
- **Check the objective *and* the mechanism.** They assert the lab's specified reachability
  *and* that it was achieved the specified way (e.g. the flow transits the router, proven by
  `tcpdump` on both legs) — so a shortcut can't earn a green check.

| Lab | Verification |
|-----|--------------|
| `lab-a02-topologies/` | ✓ `tests/test.sh <1–5>` — five sub-labs, one container |
| `lab-a03-admin-tasks/` | ✓ `tests/test.sh <1–12>` — twelve sub-labs, one container |
| `lab-a04-routing/` | ✓ `tests/routing/test.sh <1–7>` — seven sub-labs, article-04 container |
| `lab-a04-vrrp/` | ✓ `tests/vrrp/test.sh <1–2>` — two sub-labs, article-04 container |
| `lab-a04-multicast/` | ✓ `tests/multicast/test.sh <1–2>` — two sub-labs, article-04 container |
| others | _added as each lab gains a runnable, checkable topology_ |

When you build out a new lab, add a `tests/` directory following the
[Lab A02 tests](lab-a02-topologies/tests/README.md) shape: a `test.sh` entrypoint (taking a
part argument when the lab is multi-part) plus the shared `lib.sh` helpers it dispatches to.

## Index

| Lab | Sub-labs | Pairs with | What it teaches |
|---|---|---|---|
| [`lab-a01-translation/`](lab-a01-translation/) | 1 | [Article 1](../wiki/article-01-linux-for-network-engineers.md) | Read a Linux box end to end with the `iproute2` suite |
| [`lab-a02-topologies/`](lab-a02-topologies/) | 5 | [Article 2](../wiki/article-02-interfaces-namespaces-topologies.md) | Build a router, a switch, and a composed network from `iproute2` + namespaces |
| [`lab-a03-admin-tasks/`](lab-a03-admin-tasks/) | 12 | [Article 3](../wiki/article-03-common-network-admin-tasks.md) | Recurring admin tasks as one-liners: routing, ACL, VLAN, bond, NAT, SPAN, DHCP, VRF, ARP, MTU, NTP/syslog/LLDP, and full appliance |
| [`lab-a04-routing/`](lab-a04-routing/) | 7 | [Article 4](../wiki/article-04-routing-daemons.md) | FRR routing: RIB-vs-FIB, OSPF adjacency, eBGP, BGP unnumbered, BFD, persistence, journal correlation |
| [`lab-a04-vrrp/`](lab-a04-vrrp/) | 2 | [Article 4](../wiki/article-04-routing-daemons.md) §5b | First-hop redundancy with `keepalived` and FRR `vrrpd` |
| [`lab-a04-multicast/`](lab-a04-multicast/) | 2 | [Article 4](../wiki/article-04-routing-daemons.md) §7 | PIM-SM with FRR `pimd`; static mroute with `smcroute` |
| [`lab-a05-qos/`](lab-a05-qos/) | 1 | [Article 5](../wiki/article-05-production-appliance.md) | Traffic shaping and queueing with `tc`, HTB, `fq_codel` |

New labs are added here as the series progresses.
