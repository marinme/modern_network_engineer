# Lab A02 — Topologies from `iproute2`

Pairs with: [Article 2 — Interfaces, Namespaces, and Topologies in Linux](../../wiki/article-02-interfaces-namespaces-topologies.md)

## What this lab teaches

Construction, not observation. Article 1's lab had you read one Linux box; this one has you compose several into a working topology with nothing but `iproute2` and the `bridge` command. It isn't meant to be a replacement for your existing stack, but instead focus on teaching you how that stuff is likely done under the hood so that you can decompose newer technology stacks into these primitives. It is split into five sub-labs, each in its own file:

1. **[Router out of nothing](./lab-1-router.md)** — three namespaces, two veth pairs, static routes, IP forwarding. End-to-end ping verified, `tcpdump` on the middle namespace confirms forwarding.
2. **[Switch out of nothing](./lab-2-switch.md)** — a bridge inside one namespace with three host namespaces hung off it as bridge ports. MAC learning visible in `bridge fdb`, broadcast vs. unicast behaviour visible with `tcpdump -e`.
3. **[Compose them](./lab-3-compose.md)** — Lab 2's bridge wired to a Lab 1 router leg, two hosts each side. `host — switch — router — switch — host`, end to end.
4. **[SVIs: routing between VLANs on one bridge](./lab-4-svi.md)** — a VLAN-aware bridge with a per-VLAN SVI gateway, turning the L2 switch into a layer-3 switch that routes between VLANs on one box.
5. **[Trunks: carrying VLANs between switches](./lab-5-trunk.md)** — two bridges joined by one 802.1Q trunk; same-VLAN reaches across switches, different VLANs stay isolated, and the tag is visible in `tcpdump`.

Do them in order the first time — Lab 3 reuses both earlier shapes, and Labs 4–5 build on the VLAN-filtering extension at the end of Lab 2. The whole point is to type the primitives by hand once so that every higher-level wrapper (Containerlab, Docker networks, Kubernetes pod sandboxes, FRR labs) reads as "oh, that's the thing I already built."

## Prerequisites

- Docker (or another OCI runtime) installed and functional. Same as Lab A01.
- Article 1's lab done, or equivalent comfort reading `ip -br link`, `ip route`, and `tcpdump` output.
- About two hours for all five sub-labs the first time.

The lab runs entirely inside one Docker container. The container is the *workbench*; the topology you build with `ip netns add` lives in network namespaces inside that one container's kernel view. That mirrors the article's pedagogy — Article 2 is about meeting the primitive (`ip netns`, `veth`, `bridge`) before meeting the wrappers (Containerlab, Compose, K8s). Article 12 picks up the wrapper-per-node model; here, you do it by hand.

## The setup

The container source is at [`containers/article-02/`](../../containers/article-02/) at the repo root. Two equivalent ways to run it:

```bash
# Direct docker
docker build -t netmod/article-02 containers/article-02
docker run -it --rm \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  --cap-add=SYS_ADMIN \
  --security-opt apparmor=unconfined \
  --name article-02 \
  netmod/article-02

# Or via compose (builds on first run, then drops you straight in)
docker compose -f containers/article-02/docker-compose.yml run --rm lab
```

The three [caps](https://man7.org/linux/man-pages/man7/capabilities.7.html) are deliberate: `NET_ADMIN` for `ip link` / `ip route` / `ip netns`, `NET_RAW` for `tcpdump`, and `SYS_ADMIN` because `ip netns add` bind-mounts the new namespace under `/var/run/netns/` and the mount syscall needs it. `apparmor=unconfined` is necessary on Ubuntu/Debian hosts whose default Docker [AppArmor](https://wiki.ubuntu.com/AppArmor) profile blocks the mount even with `SYS_ADMIN`. None of this grants host access — the container still runs in its own namespace; you are just giving it permission to make sub-namespaces of its own.

The Dockerfile's header comment spells out exactly what each flag is for, and lists `--privileged` as the lazy-but-equivalent alternative if you prefer.

You should land at a `root@workbench:/lab#` prompt with the MOTD listing the three sub-labs. Everything in the sub-lab files runs inside that prompt — no `sudo` needed, no host networking touched.

## A note on persistence

Nothing in this lab survives the container exiting. `ip netns add` and `ip link add` write kernel state into the container's view, which evaporates when the container is removed. That is the right behaviour for a learning loop — `exit`, re-run the container, start fresh. Article 5 picks up Netplan and systemd-networkd for the persistent version of the same configuration; this lab deliberately stays volatile.

## Cleanup, up front

Inside the container, each sub-lab ends with `ip netns del <name>` per namespace. Deleting a namespace tears down every interface, address, and route inside it — including the bridge and the namespaced end of each veth pair, which the kernel garbage-collects when its peer's namespace goes away. If you get lost mid-lab, `ip netns list` shows everything you created and the following resets you to zero without leaving the container:

```bash
for ns in $(ip netns list | awk '{print $1}'); do ip netns del $ns; done
```

And if even that gets weird, `exit` the container and re-run it. That will start everything fresh.

## The sub-labs

Run them in order; each is self-contained once the workbench above is up.

| # | Lab | Builds | Verifies |
|---|-----|--------|----------|
| 1 | **[Router out of nothing](./lab-1-router.md)** | `h1 — r1 — h2`, two veth pairs, static routes, forwarding | end-to-end ping through `r1`, `tcpdump` on both legs, asymmetric-routing failure mode |
| 2 | **[Switch out of nothing](./lab-2-switch.md)** | a `br0` bridge in `sw1` with three host ports | L2 ping, `bridge fdb` MAC learning, ARP flood-then-unicast, optional 802.1Q VLAN split |
| 3 | **[Compose them](./lab-3-compose.md)** | two switches + a router, two hosts each side | same-subnet and cross-subnet ping, `traceroute` showing the bridges are invisible |
| 4 | **[SVIs](./lab-4-svi.md)** | one VLAN-aware bridge, two VLANs, an SVI gateway per VLAN | same-VLAN L2 vs inter-VLAN routing on one box, `traceroute` to the SVI, the routed-frame retag in `tcpdump` |
| 5 | **[Trunks](./lab-5-trunk.md)** | two VLAN-aware bridges joined by one 802.1Q trunk | same-VLAN across switches, cross-VLAN isolation, 802.1Q tags in `tcpdump -e`; optional inter-VLAN routing over the trunk |

## Further reading

- `man 8 ip-netns`, `man 8 ip-link`, `man 8 bridge` — the three you will reach for again and again.
- Quarkslab, "[Digging into Linux namespaces — Part 1](https://blog.quarkslab.com/digging-into-linux-namespaces-part-1.html)" — the deep dive that motivates the `/proc/<pid>/ns/` preamble in [Lab 1](./lab-1-router.md).
- `Documentation/networking/bridge.rst` in the kernel tree for VLAN-filtering bridge internals; `bridge vlan show` and the `pvid`/`untagged`/`self` flags are the working surface for Labs 4–5.
- Containerlab docs — once you have done this lab, read the [Containerlab "node kinds" page](https://containerlab.dev/manual/kinds/) and notice how each `linux` node is exactly what you just built by hand.
