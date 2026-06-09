# Lab A04 — Lab 6: Persisting FRR Config

Pairs with: [Article 4 §6](../../wiki/article-04-routing-daemons.md#persisting-frr)

Return to [Lab A04 README](./README.md) for setup instructions.

## What this section teaches

`write` (or `write memory`) saves the running FRR configuration to `/etc/frr/<ns>/frr.conf`. The config file looks like a Cisco config — IOS-shaped, human-readable. The session exercises `write`, inspects the resulting file, confirms the config survives a daemon restart, and deliberately breaks the file to observe how FRR fails loudly on a bad config.

## Build the topology

Any OSPF or BGP config from Labs 2–5 should be running. If you have been following in order, the BGP + BFD config is active.

## Part A — Save the running config

```bash
/lab/frrvtysh r1
r1# write
r1# exit
```

Inspect the file:

```bash
cat /etc/frr/r1/frr.conf
```

It looks like a Cisco config: `router bgp 65001`, `bgp router-id`, `neighbor`, `address-family`. This is the integrated config format — one file for all daemons, enabled by `service integrated-vtysh-config` in `/etc/frr/r1/vtysh.conf`.

Save all three routers:

```bash
for ns in r1 r2 r3; do
    ip netns exec "$ns" vtysh -N "$ns" -c 'write'
    echo "$ns: $(wc -l < /etc/frr/$ns/frr.conf) lines saved"
done
```

## Part B — Verify config survives daemon restart

```bash
# Restart FRR in r1
systemctl restart frr@r1

# Wait for daemons to come back up (watchfrr takes a moment)
sleep 5
systemctl status frr@r1 --no-pager

# Confirm sessions re-established
ip netns exec r1 vtysh -N r1 -c 'show ip bgp summary'
```

BGP should come back to `Established` within the BGP hold-time. OSPF should re-establish `Full` within seconds.

## Part C — Intentionally break frr.conf and observe the failure

This exercise is the "commit validation" equivalent — bad configs fail loudly at load time, not silently at runtime:

```bash
# Break r1's config deliberately
cp /etc/frr/r1/frr.conf /etc/frr/r1/frr.conf.backup
echo "INVALID SYNTAX HERE" >> /etc/frr/r1/frr.conf

# Restart — watch it fail
systemctl restart frr@r1
sleep 3
systemctl status frr@r1 --no-pager

# Read the error — FRR logs the line number
journalctl -u frr@r1 -n 20 --no-pager | grep -E '(error|Error|line |syntax)'
```

FRR will log something like `%LIB-3-MEMFAIL: frr.conf:NN: parser error — unknown token 'INVALID'` and the daemon will exit (watchfrr will keep trying to restart it).

Restore the good config:

```bash
cp /etc/frr/r1/frr.conf.backup /etc/frr/r1/frr.conf
systemctl restart frr@r1
sleep 5
ip netns exec r1 vtysh -N r1 -c 'show ip bgp summary'   # should be Established again
```

## Part D — The `show running-config` ↔ `frr.conf` relationship

```bash
# Running config (live, from daemon)
ip netns exec r1 vtysh -N r1 -c 'show running-config'

# On-disk config (saved, loaded at next restart)
cat /etc/frr/r1/frr.conf

# Diff them — they should match after 'write'
diff <(ip netns exec r1 vtysh -N r1 -c 'show running-config' 2>/dev/null | grep -v '^!' | grep -v '^$') \
     <(grep -v '^!' /etc/frr/r1/frr.conf 2>/dev/null | grep -v '^$') || echo "(differences found — run 'write' to sync)"
```

## Test your work

```bash
./tests/routing/test.sh 6
```

The checker confirms: `frr.conf` is non-empty, contains a router stanza, and the running config matches the on-disk config.

## Comprehension questions

<details>
<summary>Answers (click to expand)</summary>

**Q: Is there a `copy running-config startup-config` equivalent?**
A: `write` (or `write memory`) is the direct equivalent. In FRR's integrated mode, it writes to `frr.conf`. `write file /tmp/backup.conf` writes to an arbitrary file. There is no NVRAM concept — `frr.conf` is just a file on the filesystem.

**Q: What is the difference between `write` and `vtysh -w`?**
A: Inside `vtysh`, `write` saves the running config. From the shell (not in a vtysh session), `vtysh -w` does the same thing: `ip netns exec r1 vtysh -N r1 -w`. Both produce the same `frr.conf`.

**Q: What is `watchfrr`'s role in persistence?**
A: `watchfrr` is the supervisor process — it starts all enabled daemons, monitors them for crashes, and restarts them if they die. On restart, each daemon reads `frr.conf` (or its own per-daemon config file if not using integrated mode) and restores its configuration. If `frr.conf` is broken, the daemon exits, watchfrr retries, and the loop continues until the file is fixed. Check `journalctl -u frr@r1 -f` to see the restart loop.

</details>

## Teardown

No teardown. The saved configs persist for Lab 7.

---

Next: [Lab 7 — Journal Correlation](./lab-7-journal-correlation.md)
