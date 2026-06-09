# Lab A04 — Lab 7: Journal Correlation on Flap

Pairs with: [Article 4 §8](../../wiki/article-04-routing-daemons.md#reading-what-just-happened-journalctl-against-a-live-frr-session)

Return to [Lab A04 README](./README.md) for setup instructions.

## What this section teaches

The journal unifies many writers. A single link flap produces two entries from two different processes (the kernel logs the link state change, `bgpd` or `ospfd` logs the session reset milliseconds later), separated by a few milliseconds. This section makes that visible, then shows how a structured `jq` query can interleave both writers by timestamp.

The mapping table that Article 1 promised and Article 4 §8 delivers:

| Cisco IOS | Linux journal |
|---|---|
| `show logging` | `journalctl -e` |
| `show logging \| include OSPF` | `journalctl -u frr@r1` |
| `show logging \| include LINK` | `journalctl -k -g 'link'` |
| `terminal monitor` | `journalctl -u 'frr@*' -f` |

## Build the topology

The full topology from Labs 2–6 should be running (OSPF + BGP + BFD, FRR configs saved).

## Part A — The three-shell exercise

Open a `tmux` session inside the container (or three separate shells via `docker exec`):

```bash
# In the container, start tmux
tmux new-session -s journal \; \
  split-window -h \; \
  split-window -v \; \
  select-pane -t 0
```

**Pane 0 — FRR events:**
```bash
journalctl -u 'frr@*' -f
```

**Pane 1 — kernel link events:**
```bash
dmesg -wT
```

**Pane 2 — control:**
```bash
# Flap the r1↔r2 veth
ip link set r1-r2 down
sleep 3
ip link set r1-r2 up
```

### What to look for

1. **Pane 1 (dmesg) shows the link event first** — within milliseconds of `ip link set r1-r2 down`, the kernel logs: `r1-r2: renamed from r1-r2` or `carrier lost` / `link is not ready`. The exact message varies by kernel version.

2. **Pane 0 (FRR) shows the session reset a few milliseconds later** — `bgpd` logs `%BGP-5-ADJCHANGE: neighbor r1-r2 Down` or similar. If BFD is active, `bfdd` logs the peer state change before bgpd does.

3. **After `ip link set r1-r2 up`**, the inverse happens: kernel logs link-up, then FRR logs the adjacency reform.

The temporal ordering (kernel first, then daemon) is the key observation. It proves that these are two separate writers, not one event logged twice.

## Part B — The daemon-only event

Now induce an event that the kernel does NOT see:

```bash
# Pane 2: clear BGP session without touching the link
ip netns exec r1 vtysh -N r1 -c 'clear bgp *'
```

Observe:
- **Pane 1 (dmesg)**: nothing. The link is still up; the kernel saw no physical event.
- **Pane 0 (FRR)**: `bgpd` logs the session reset and re-establishment.

This is the "many writers" distinction the article describes. A daemon-internal event leaves no kernel trace. When you see a BGP reset in `journalctl -u frr@r1` but nothing in `journalctl -k`, the cause is inside FRR (config change, `clear bgp`, route flap due to policy), not a link failure.

## Part C — The structured cross-writer query

```bash
journalctl --since '5 min ago' \
  -o json-pretty \
  --no-pager \
  | jq -c 'select(
        ._SYSTEMD_UNIT == "frr@r1.service"
        or .SYSLOG_IDENTIFIER == "kernel"
      )
      | {
          t: (.__REALTIME_TIMESTAMP | tonumber / 1000000 | todate),
          writer: (._SYSTEMD_UNIT // .SYSLOG_IDENTIFIER),
          msg: .MESSAGE
        }'
```

This query:
- Selects entries from either FRR (`frr@r1.service`) or the kernel (`kernel` syslog identifier)
- Converts the microsecond timestamp to a human-readable ISO datetime
- Prints `{t, writer, msg}` — interleaved in timestamp order

You will see the kernel entry (from the flap) appear before the FRR entry, with the timestamps differing by single-digit milliseconds. That is the cross-writer correlation the article promised.

## Part D — Optional: watch nftables log entries in the same stream

If you add a logging nftables rule in a namespace (from Article 3's patterns):

```bash
ip netns exec r1 nft add table inet log-demo
ip netns exec r1 nft add chain inet log-demo forward '{ type filter hook forward priority 0; }'
ip netns exec r1 nft add rule inet log-demo forward log prefix '"FORWARD: "' accept
```

Then generate some forwarded traffic (ping across r1) and check:

```bash
journalctl -f -k | grep FORWARD
```

The `nft log` entry appears in `journalctl -k` (kernel syslog) alongside the link events — same stream, same format, same `jq` query can select all three (FRR, kernel link events, nftables log).

Cleanup the rule:

```bash
ip netns exec r1 nft delete table inet log-demo
```

## Test your work

```bash
./tests/routing/test.sh 7
```

The checker confirms: `frr@*` units have journal entries, kernel has journal entries, json-pretty output is parseable by jq.

## Comprehension questions

<details>
<summary>Answers (click to expand)</summary>

**Q: The kernel log showed the link down, but `dmesg -wT` in the container shows nothing. Why?**
A: The kernel logs link events in the namespace where the interface lives, but `dmesg` reads from the host-level kernel ring buffer. If the interface is in a network namespace, the event is logged in the global kernel log (all namespaces share one kernel), and `dmesg -wT` inside the container should show it because the container shares the host kernel. If you see nothing, check that you flapped the interface at the container-level (`ip link set r1-r2 down`, not `ip netns exec r1 ip link set r1-r2 down`) — veth pairs are moved into namespaces but the link-state event is logged globally.

**Q: The FRR log shows `%BGP-5-ADJCHANGE: neighbor r1-r2 Down Interface flap`. Is that line from bgpd or bfdd?**
A: If BFD is configured, the `Interface flap` reason means BFD detected the failure and notified bgpd. If BFD were not configured, the reason would be `Hold Timer Expired` (90 seconds later). The unit tag in the journal tells you which FRR process wrote the line — `frr@r1.service` covers all FRR daemons in that namespace since they are managed by the same unit.

**Q: Can I filter by a specific daemon inside frr@r1.service?**
A: Yes, via the `SYSLOG_IDENTIFIER` field. FRR daemons log with identifiers like `bgpd`, `ospfd`, `bfdd`:
`journalctl -u frr@r1.service SYSLOG_IDENTIFIER=bgpd -f`

</details>

## Teardown

```bash
exit            # exit the workbench shell
                # docker compose run --rm removes the container
                # all namespaces and FRR state disappear with it
```

---

You have finished all seven Lab A04 routing sub-labs.

Continue with:
- [Lab A04 — VRRP](../lab-a04-vrrp/) — first-hop redundancy
- [Lab A04 — Multicast](../lab-a04-multicast/) — PIM-SM with FRR `pimd`
