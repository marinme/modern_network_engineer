
# Linux for Network Engineers

## Why this article exists

If you have spent the last fifteen years inside Cisco IOS, NX-OS, or Junos, you already understand routing. You know longest-prefix match. You know what ARP is doing. You can read a routing table and tell me which next-hop is going to win and why. That networking expertise is not what this series is here to teach.

The problem is that almost every modern network tool runs on Linux, and a growing number of the devices themselves *are* Linux underneath a thin vendor veneer. NetBox runs on Linux. Containerlab runs on Linux. Your CI runner is Linux. Arista EOS is Linux. Cumulus is Linux. SONiC is Linux. The eBPF programs steering packets in a Kubernetes cluster are Linux. The control plane of every major SD-WAN product on the market shipped as a Linux daemon before it shipped as a SaaS endpoint. It's my opinion that you cannot opt out of Linux fluency and stay effective in this work.

The good news is that the conceptual lift isn't that big. What you need is the vocabulary, the Linux name for the thing you already understand and some practice in doing it. That is what this article gives you, and it is also the cleanest possible introduction to using an AI assistant in your practice: as a translator between two dialects of the same language.

This is the first of five Linux articles. This one is **the translation**: read Linux output, type Linux commands, recognize the IOS shape underneath. The next four go deeper. [[article-02-interfaces-namespaces-topologies]] takes you into interface types and namespaces and shows you how to build a router and a switch out of primitives. [[article-03-common-network-admin-tasks]] is the recurring-jobs reference: VLAN trunk, NAT, ACL, DHCP, port mirror, all the things you do in a normal month. [[article-04-routing-daemons]] is the routing-daemon deep dive: FRR, OSPF, BGP, BFD, VRRP, multicast. [[article-05-production-appliance]] is the production-hardening article: `systemd-networkd` persistence, `nftables` at scale, sysctl/NIC tuning, QoS, and a structured troubleshooting workflow.

What this article expects from you is the years of CLI fluency and networking expertise you already have, ready to be translated into Linux. The [[assumed-networking-knowledge]] page lays out the specific networking fundamentals this article — and the rest of the series — expects you to already own; if a substantial chunk of it feels unfamiliar, shore that up before going further. It also expects basic Linux comfort: SSH, filesystem navigation, and routine system administration. Plenty of "Linux for network engineers" articles on the internet stop at that introductory layer — go to them if you need it, and come back here when you want to start connecting Linux primitives to the expertise you already own.
## The translation table

Most of what you type into a router in a given week has a one-line Linux equivalent. Put them side by side and the mapping becomes obvious:

| Cisco IOS                         | Linux                                                                                                                                                                   |
| --------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `show ip route`                   | [`ip route show`](https://man7.org/linux/man-pages/man8/ip-route.8.html)                                                                                                |
| `show ip route 10.0.0.0`          | `ip route get 10.0.0.0`                                                                                                                                                 |
| `show interfaces`                 | [`ip -s link`](https://man7.org/linux/man-pages/man8/ip-link.8.html)                                                                                                    |
| `show ip interface brief`         | [`ip -br addr`](https://man7.org/linux/man-pages/man8/ip-address.8.html)                                                                                                |
| `show ip arp`                     | [`ip neigh`](https://man7.org/linux/man-pages/man8/ip-neighbour.8.html)                                                                                                 |
| `show mac address-table`          | [`bridge fdb show`](https://man7.org/linux/man-pages/man8/bridge.8.html)                                                                                                |
| `show running-config`             | `cat /etc/network/interfaces`, [`nft list ruleset`](https://wiki.nftables.org/wiki-nftables/index.php/Main_Page), `systemctl cat ...`                                   |
| `show vrf`                        | [`ip vrf show`](https://man7.org/linux/man-pages/man8/ip-vrf.8.html) (and [`ip netns list`](https://man7.org/linux/man-pages/man8/ip-netns.8.html) for namespace VRFs)  |
| `ping`                            | [`ping`](https://man7.org/linux/man-pages/man8/ping.8.html)                                                                                                             |
| `traceroute`                      | [`traceroute`](https://man7.org/linux/man-pages/man8/traceroute.8.html) or [`mtr`]([https://man7.org/linux/man-pages/man8/mtr.8.html](https://linux.die.net/man/8/mtr)) |
| `debug ip packet` + ACL           | [`tcpdump -i <iface> <filter>`](https://man7.org/linux/man-pages/man8/tcpdump.8.html)                                                                                   |
| `access-list` / `ip access-group` | `nft add rule ...`                                                                                                                                                      |
| `clear ip route *`                | `ip route flush table main` (don't)                                                                                                                                     |
| `write memory`                    | edit `/etc/systemd/network/*.network` or [`netplan apply`](https://netplan.readthedocs.io/en/latest/netplan-apply/)                                                     |
| `enable` / `configure terminal`   | `sudo` (and that's it — no config mode)                                                                                                                                 |
| `terminal length 0`               | pipe to `cat` or set `PAGER=cat`                                                                                                                                        |
| `show logging`                    | [`journalctl`](https://man7.org/linux/man-pages/man1/journalctl.1.html) / `journalctl -u <unit>` / [`dmesg -wT`](https://man7.org/linux/man-pages/man1/dmesg.1.html)    |

`ip route show` reads the same forwarding information base the kernel uses to make a forwarding decision. The output is plainer than IOS — no banners, no pager, no `--More--` — but the information is the same.

A handful of things don't map cleanly, and those are the ones worth naming up front because they will trip you up if you assume they will:

- **RIB versus FIB visibility.** On IOS, `show ip route` is RIB and you reach for `show ip cef` to see the FIB. On Linux, the kernel routing table you see with `ip route show` *is* the forwarding table. The RIB lives in whatever routing daemon you are running (FRR, BIRD), and you query it with that daemon's own CLI. If you have no daemon, there is no RIB; the routes you installed by hand are the whole picture. [[article-04-routing-daemons]] picks this up properly.
- **No "interface" vs "subinterface" distinction.** A Linux 802.1Q subinterface is a real interface with its own name (`eth0.100`) and shows up in `ip link` alongside its parent. `show interfaces` does not split parent and child the way IOS does.
- **`proto` codes on routes.** Routes carry a `proto` field showing who installed them — `kernel`, `static`, `dhcp`, `bgp`. That field has no IOS equivalent; the closest is the route source character in `show ip route` (`B`, `O`, `S`). Worth knowing because when something installed a route you didn't expect, `ip route show proto bgp` is how you find it.
- **No "no" prefix.** Every IOS command has a `no` form. Linux has `add` and `del` (and occasionally `replace`, which is genuinely useful — `ip route replace` is atomic in a way `no ip route ... / ip route ...` is not on a router).
- **No config mode and no commit.** Every `ip` and `nft` command takes effect immediately. There is no `commit confirmed`, no `wr mem`, no transaction. Persistence is a separate concern (you write files for that, see Article 5); the running state is whatever the kernel currently believes.
- **Logs come from many writers, not one box.** `show logging` is one buffer with one writer; `journalctl` is one buffer with *many* writers. Kernel link transitions land under `journalctl -k` (or `dmesg -wT`), `systemd-networkd` address and DHCP events under `journalctl -u systemd-networkd`, and routing-daemon adjacency changes under `journalctl -u frr` (or per-protocol `-u bgpd`, `-u ospfd`). Each entry carries structured fields you can query with `-o json`. A single network event often produces two entries from two writers (the kernel logs the link bounce; the daemon logs the session reset milliseconds later), and correlating them by timestamp is the everyday journal-reading skill. [[article-04-routing-daemons]] demonstrates this against a live FRR session, which is the first place in the series where the cross-writer correlation has something interesting to say.

The first prompt to try with an AI assistant looks exactly like this table, one row at a time. Paste a command you would have typed on a 6500, ask for the Linux equivalent and the gotchas. The answer is verifiable against your own competence: you know what `show ip route` was supposed to do, so you can tell immediately if the translation is wrong.

## A first look at `nftables`

The translation table points at `nft` and `nft list ruleset` and the gotchas note that `nft` commands take effect immediately. Two facts about the wider context are worth pinning down before the lab, because they will save you confusion the first time you see a real ruleset. **This section is recognition only — the lab builds the structure hands-on; Article 3 covers usage (ACL, NAT, port-forward); Article 5 goes deep on hooks, families, sets, maps, and NAT chains.**

First, `nftables` is the modern Linux packet-filter framework — successor to `iptables`, which succeeded `ipchains`. The CLI is `nft`; the kernel loads its compiled ruleset atomically. The structural model is three levels: **table → chain → rule**, where a table is a container scoped to an address family (`inet` covers v4+v6 and is the modern default), a chain attaches to a kernel **hook** (`input`, `output`, `forward`, `prerouting`, `postrouting`) with a default policy, and a rule is a match plus a verdict. The lab walks you through building exactly one of these from scratch, so the shape lands by typing rather than by reading.

Second, the box you are looking at probably has a frontend in front of `nft`. On RHEL/Fedora it is `firewalld` (`firewall-cmd`, with `trusted` / `public` / `dmz` zones); on Ubuntu it is `ufw`. Both write their rules through `nftables` under the hood, so `nft list ruleset` is the ground-truth view even when neither tool is what an admin uses day-to-day. The legacy `iptables` command still exists on most distributions but is now `iptables-nft`, a compatibility shim onto the same kernel framework.

The series teaches `nftables` directly — not the frontends — because **on every Linux box this series cares about, more than one thing writes to the kernel ruleset and no frontend shows you all of them.** Docker installs its own NAT chains and a `DOCKER-USER` filter chain. Kubernetes' `kube-proxy` installs service-routing rules. `libvirt`, `podman`, `fail2ban`, and `tailscale` each install their own. A routing daemon may install policy-routing-adjacent rules. `firewall-cmd --list-all` and `ufw status` only show you what that frontend installed; they don't show you Docker's chains, and they will happily tell you a port is permitted while a rule from another producer is dropping the traffic. `nft list ruleset` is the only view that shows the complete kernel state, which means it is the view you reach for when something is wrong. Add to that the cross-distro reality (`firewalld` on RHEL, `ufw` on Ubuntu, raw `nft` on Alpine/container images, nothing at all on minimal server installs) and the leakiness of the frontend abstractions the moment you need NAT, conntrack zones, or mark-based routing, and the common substrate is the only thing worth learning once. The frontends and their persistence stories come with Article 5.

## The `ip` suite

`ifconfig`, `route`, `arp`, and `netstat` are the previous-generation tools. They still work on the older boxes you SSH into and modern packagers still ship them, so don't pretend they're gone — but on any current Linux the canonical tools are [`ip`](https://man7.org/linux/man-pages/man8/ip.8.html) from `iproute2` and [`ss`](https://man7.org/linux/man-pages/man8/ss.8.html). The reason they replaced their predecessors matters, because it is the same reason the rest of the modern Linux networking stack works the way it does: **`ip` talks to the kernel over netlink, a structured request/response protocol, while `ifconfig` and `netstat` read formatted strings out of `/proc`.** That difference is the whole story. Netlink gives `ip` access to things `/proc` never exposed (multiple routing tables, namespaces, modern interface types, per-route metrics), and it gives the kernel a stable interface to evolve without breaking tools that hadn't been updated yet. If you have wondered why `ifconfig` stops being useful the moment you touch a namespace or a VRF, that is the answer — it is reading a view that was never meant to describe those things.

The `ip` command's syntax is consistent and worth internalising once: **`ip [MODIFIERS] OBJECT COMMAND [ARGS]`**. The objects map cleanly to the layers you already think in:

- `ip link` — Layer 1/2. Interfaces, MAC addresses, MTU, link state. `ip link set eth0 up` is `no shutdown`. `ip link add` creates every Linux interface type — `veth`, `bridge`, `vlan`, `vxlan`, `bond`, `wireguard`, `gre` — and is where Article 2 lives in detail.
- `ip addr` — Layer 3 addressing. `ip addr add 10.0.0.1/24 dev eth0` is `ip address 10.0.0.1 255.255.255.0`.
- `ip route` — the routing table. `ip route add 10.1.0.0/24 via 10.0.0.2` is `ip route 10.1.0.0 255.255.255.0 10.0.0.2`. `ip route get <addr>` asks the kernel which route it would actually use — the closest equivalent to `show ip cef <prefix>` on IOS, and the right reflex for "what will happen if I send a packet to X."
- `ip neigh` — the ARP table (and its IPv6 sibling, NDP). Each entry carries a state — `REACHABLE`, `STALE`, `FAILED`, `PERMANENT` — that tells the kernel whether to re-ARP before sending a frame. `arp -a` glossed over this; `ip neigh` puts it front and centre.
- [`ip rule`](https://man7.org/linux/man-pages/man8/ip-rule.8.html) — policy routing. The thing you reached for VRF-lite to do on IOS. Multiple routing tables selected by source address, mark, interface, or any combination.
- `ip vrf` — the operational interface to Linux VRFs (which are a `vrf` master device plus a routing table plus `ip rule` entries — Article 4 has the depth). `ip vrf exec <name> <cmd>` runs a command in a specific VRF, which is the Linux equivalent of `routing-context vrf X` on IOS.
- `ip netns` — network namespaces, the substrate primitive [[article-02-interfaces-namespaces-topologies]] builds on. Adjacent to but distinct from `ip vrf`: namespaces isolate everything (interfaces, sockets, conntrack, sysctls); VRFs isolate only the L3 forwarding plane.
- `ip maddr` and `ip mroute` — multicast group memberships per interface, and the kernel's multicast forwarding table. The PIM control plane lives in a daemon ([[article-04-routing-daemons]] §12b); the kernel state lives here.
- `ip monitor` — live netlink event stream. Run it in a second window while you make changes and you'll see every interface, address, route, and neighbor event as it happens. The Linux analog of `terminal monitor` plus `debug ip routing`, but structured. Article 5's troubleshooting workflow reaches for this when something is changing and you want to watch.

Modifiers compose with any object. `-br` gives brief columnar output (great for eyeballs); `-d` gives detailed output (interface types, link-netns, queue counts); `-s` adds counters (`-s -s` doubles them, splitting error categories); `-j` emits JSON; `-c` colours the output where supported. Once you know the modifiers, every `ip` object inherits them — `ip -br link`, `ip -br addr`, `ip -s link`, `ip -j route show`, `ip -d link show eth0` — the syntax pays back the small investment of learning it once.

Two capabilities the suite gives you that IOS makes you fight for:

1. **Multiple routing tables, native.** `ip route show table 100`. `ip rule add from 192.168.1.0/24 lookup 100`. No VRF declaration, no route-target dance. You just have tables (255 of them by default, identified by number or by name in `/etc/iproute2/rt_tables`), and you have rules that pick a table. The rule list is ordered by priority; the first match wins. This is genuine policy-based routing as a first-class kernel feature, not an overlay. If you have ever wanted to send traffic from one source subnet out a different uplink without touching BGP, you have wanted `ip rule`. The kernel always consults three tables in priority order — `local` (the box's own addresses), `main` (what you usually call "the routing table"), `default` (fallback) — and `ip rule show` lists them. Adding `table 100` and a rule to select it is a two-command operation.
2. **Structured output as the default.** `-j` emits JSON for every subcommand. `ip -j addr show | jq '.[] | {ifname, addr_info: .addr_info[0].local}'` is the kind of one-liner that replaces a hundred-line screen-scraping script. The fact that the canonical Linux networking tool emits structured output by default is the single biggest reason network automation feels different on Linux than it does on a router CLI: you are not parsing prose, you are reading a data structure. Combined with the netlink point above, the implication is unified: `ip` is reading the kernel's native data model and rendering it for you, and `-j` is the same data minus the rendering. We will lean on this from Article 6 onward; remember it lives here.

The gotcha worth naming once, because it surprises every IOS engineer the first time: **`ip` commands take effect immediately and are not persistent.** No config mode, no commit, no `wr mem`. The kernel's running state is the truth; persistence is a separate concern handled by `systemd-networkd`, Netplan, or NetworkManager (Article 5). This is the same point the gotchas list in the translation table made, but it matters more here because the `ip` suite is where you'll feel it. The flipside is that `ip route replace` exists and is atomic — there is no "two commands and a hope" gap a `no ip route ... / ip route ...` pair leaves on a router. The kernel's data model rewards careful use and punishes guessing; learning the shape of the model pays back the rest of this article.

## Observation and capture

When something is wrong, three tools cover most of the ground.

`ss` replaces `netstat`. `ss -tnp` lists TCP sockets with the owning process. `ss -lntp` lists what's listening. `ss state established '( dport = :443 or sport = :443 )'` filters down to current TLS conversations. The filter language is its own thing and worth ten minutes of reading; once you have it, debugging "what is this box actually talking to" becomes a one-liner.

`tcpdump` is `tcpdump`. The BPF filter syntax (`host 10.0.0.1 and port 179`) is the same syntax you have been pasting into engineering tickets for a decade. A few flags worth knowing:

- `-i any` captures across all interfaces, useful in a namespaced environment when you don't yet know which interface the traffic is hitting.
- `-w file.pcap` writes a capture you can open in Wireshark, which remains the right tool for anything past a few packets.
- `-nn` skips name and port resolution. Always pass it. DNS lookups during a capture will lie to you about latency and occasionally hang the capture entirely.
- `-c 100` caps the capture at 100 packets and exits. Save yourself from a runaway `tcpdump` on a busy interface.
- `-e` shows link-layer headers, including the source MAC. The moment you are debugging a layer-2 problem on a Linux bridge, you will reach for this.

`ip -s link` shows interface counters, the equivalent of `show interfaces` for drop and error counts. `ip -s -s link show dev eth0` doubles up the `-s` to show detailed drop categorization (TX errors split by cause). [`ethtool -S eth0`](https://man7.org/linux/man-pages/man8/ethtool.8.html) goes deeper still, into NIC-level stats — ring buffer drops, checksum offload counters, the kind of detail that matters when you suspect the NIC and not the kernel.

When you ask an AI to read a `tcpdump` output you don't recognize, give it the command you ran and the output. It will tell you what protocol it sees and what the conversation looks like. You verify by asking yourself "does that match the network event I was investigating?" — same loop as before.

## A worked translation: read a Linux box

The exercise for this article is observation, not construction. Topology building is Article 2. Every reader looks at the same Linux box — a small container the series ships with — so the output on your screen matches the output the lab describes.

Go run it now: **[Lab A01 — Read a Linux Box](../labs/lab-a01-translation/)**. Twelve sections, about forty-five commands, two shells, one container, nothing touched on your host's networking. You'll exercise every row of the translation table on a running kernel, build a minimal `nftables` ruleset from scratch, and break and restore the default route to feel how the running-state model behaves under your hands. Come back here when you've finished — the AI-fits-here framing in the next section lands sharper after you've felt the immediacy of `ip` against a real box.


## Where the AI fits

This is the first article in the series, so it sets the frame the other articles spend down. The frame is one sentence: **the agent is a colleague you are teaching to do your job, not a black box that does the job for you.**

You have twenty years of mental models from running real networks. You know what good looks like. What you lack is the Linux vocabulary, and that asymmetry is exactly what an LLM closes well. The right first use is **translator and explainer**, not actor. Paste an IOS construct, get the Linux equivalent and the bits that don't map cleanly — FIB versus RIB visibility, namespace scoping, the `proto` codes on `ip route show`. Paste an unfamiliar command output, get a plain-English read of what it does and what it would have looked like as an ACL or a `show` command.

In Article 1, the agent has no tools. It cannot run commands, it cannot touch your lab, it cannot change anything. That is by construction: you are the one typing every command, the agent only proposes. The verification loop is tight because you can tell immediately when a translation is wrong — you understand the source side. Hold onto that loop. Every later article in this series widens what the agent is allowed to do, and the only thing that keeps the widening safe is the habit of verification you build here.

The prompt shape that works is concrete on both ends. Bad: "how do I do networking on Linux." Good: "On a host with `iproute2` but no `ifconfig`, what's the equivalent of `show ip interface brief` and where does the output differ?" Name the source-side construct, name the goal, name the constraint. The answer comes back verifiable, and you build the muscle memory of asking questions the agent can actually answer.

Three prompts worth keeping in a snippet file, since you will reuse the shape of them constantly:

> "Translate this IOS configuration block to its Linux `iproute2` and `nftables` equivalents. Flag anything that does not map one-to-one and explain why. Configuration: `<paste>`."

> "Here is output from `<Linux command>` on a host I do not own. Read it as if you were explaining it to a network engineer who has never worked on Linux. Call out anything that would surprise someone coming from IOS or NX-OS."

> "I want to achieve `<networking goal>` on a Linux host. List the two or three different Linux mechanisms that could do this, with a one-sentence trade-off for each. Do not write any commands yet."

The third one is the most important. The failure mode with AI assistants is to ask "give me the command" and get a confident wrong answer. Asking for the menu of approaches first lets you pick the one that fits your environment, and only then drop into command-level detail. It is also closer to how a senior engineer thinks: the command is the last step, not the first.

Example:
>Translate this IOS configuration block to its Linux `iproute2` and `nftables` equivalents. Flag anything that does not map one-to-one and explain why. Configuration: 
`interface gigabitEthernet0/1 
`  switchport access vlan 10
`  description USER PORT JACK S1-10
`  spanning-tree portfast

Gives me an explanation of the mapping, verification commands, and the linux commands to do the work.
```
# "The switch": a VLAN-aware bridge
ip link add name br0 type bridge vlan_filtering 1
ip link set dev br0 up

#"interface gigabitEthernet0/1" -> enslave the physical NIC to the bridge
ip link set dev eth0 master br0
ip link set dev eth0 up

#"switchport access vlan 10"
bridge vlan add dev eth0 vid 10 pvid untagged
    
# strip the default VLAN 1 membership
bridge vlan del dev eth0 vid 1  

#"description USER PORT JACK S1-10"
ip link set dev enp0s1 alias "USER PORT JACK S1-10"
```
```

## What this series replaces and what it doesn't

A fair worry, reading this far: the IOS world gives you safety features that haven't shown up in any of the translations yet. `archive` and `configure replace`. `commit confirmed`. TACACS+ per-command authorization with command accounting. None of those have a one-line Linux equivalent and pretending otherwise would lose your trust the first time you typed a command and watched it take effect with no net underneath.

The honest answer is that the modern stack replaces those features with a *discipline*, not a tool. Version control ([[article-06-git]]) is your archive and your change history. Code review (also Article 6) is your second pair of eyes. CI gating ([[article-22-ci-cd]]) is your `commit confirmed` — proposed changes run in a lab topology before they reach production. Source-of-truth ([[article-14-netbox]]) is what makes any of that auditable across more than one box. None of those replacements is in this article, because this article is the on-ramp; but they are real, they are in the series, and the [[legacy-config-coverage-map]] page walks the whole inventory of legacy config items and where each one lives.

A few things the series does *not* replace, and you should know up front:

- **EIGRP, DMVPN, MPLS L3VPN, classic PIM multicast, IPsec site-to-site as a vendor feature** — the series moves past these rather than reproducing them. EIGRP is proprietary. MPLS L3VPN's modern campus/DC successor is EVPN-VXLAN ([[article-17-vxlan-evpn]]). If you support these in production today, you keep doing so on your vendor gear; the Linux stack is additive to that work, not a replacement for it.
- **Switch-side hygiene features — storm control, DHCP snooping, dynamic ARP inspection, IP source guard** — the Linux bridge doesn't reproduce these. They stay vendor-NOS features in the foreseeable future.
- **Per-command TACACS+ authorization with command accounting** — sudoers, FreeIPA, and bastions are coarser. The series leans on Git audit + CI gating to recover most of the audit value, but if your shop is regulated to a level that mandates per-command TACACS accounting, you keep TACACS. The two worlds coexist.

Read those gaps as honesty, not weakness. The series teaches the surface area where Linux fluency pays off this quarter; it doesn't pretend your vendor gear is going away.

## What you should be able to do now

- Read a Linux routing table, interface list, neighbor table, and socket table and predict what each is telling you in IOS terms.
- Reach for `ip route get`, `ip -j`, and the `-br` and `-s` flags without thinking.
- Capture traffic with `tcpdump` using the five flags worth memorizing (`-i any`, `-w`, `-nn`, `-c`, `-e`).
- Translate roughly half of your IOS muscle memory into `ip`-suite equivalents on sight, and look up the other half quickly.
- Use an AI assistant as a vocabulary translator with a verification loop intact.

## What comes next

The next three articles take the substrate this one introduced and build it out:

- [[article-02-interfaces-namespaces-topologies]] — interface types (veth, bridge, vlan, vxlan, bond, wireguard, etc.), network namespaces, and the labs where you build a working router and a working switch out of `iproute2` alone.
- [[article-03-common-network-admin-tasks]] — the recurring-jobs reference. Twenty common network-admin tasks done in base Linux, with verification for each.
- [[article-04-routing-daemons]] — FRR for OSPF, BGP, BGP unnumbered, BFD, VRRP, and multicast (PIM-SM); the RIB-vs-FIB model; journal correlation against a live FRR session; the series' first generative LLM use case.
- [[article-05-production-appliance]] — production hardening: `systemd-networkd` / Netplan / NetworkManager for persistence, `nftables` in depth (hooks, sets, maps, NAT chains), sysctl / NIC / IRQ tuning, QoS with `tc`, and a structured troubleshooting workflow.

After those five articles, every later article in the series can assume Linux fluency without re-teaching it.
