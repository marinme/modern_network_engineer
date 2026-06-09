# Lab A03 — verification tests

Automated checkers for [Lab A03 — Common Network-Admin Tasks](../README.md). They run **after** you build a sub-lab inside the [`containers/article-03`](../../../containers/article-03/) workbench and confirm the finished topology actually meets the lab's objective.

Lab A03 is multi-part (twelve sub-labs that share one container), so a single `test.sh` dispatcher takes the part you want to verify.

## Running

From inside the workbench container, the `tests/` directory is mounted read-only at `/lab/tests`. Run from `/lab`:

```bash
./tests/test.sh          # list available parts
./tests/test.sh 1        # verify Lab 1 (routing-failover)
./tests/test.sh 5        # verify Lab 5 (nat-pat)
```

Part numbers, full slugs, and short names all work:

```bash
./tests/test.sh 7                # by number
./tests/test.sh 7-dhcp           # by full slug
./tests/test.sh dhcp             # by short name
```

Exit `0` if all checks passed, `1` if any check failed, `2` on a setup error (missing binary or wrong part name).

## Design principles

- **Verify-only / non-destructive.** Scripts never create a namespace, address, route, sysctl, nft rule, or any other state. They discover what you built and check whether it meets the lab's objective.
- **Auto-discovering.** Scripts find namespace names, IP addresses, and roles from live kernel state. You can name your namespaces anything (`r`, `router`, `fw`, `gw`…) and the tests will still work.
- **Objective + mechanism.** Each test checks *that* the goal was achieved (e.g. reachability) *and* that it was achieved *the right way* (e.g. the nft ruleset actually contains the ct state rule, not just that a ping happened to succeed).
- **Bash only.** No Python, no Go, no external test runners.

## Files

| File | Purpose |
|------|---------|
| `test.sh` | Dispatcher: `test.sh <N>` routes to the right checker. Auto-discovers parts from `test-lab-*.sh` filenames. |
| `lib.sh` | Shared helpers: `pass`/`fail`/`section`/`finish`, `require_cmds`, read-only namespace introspection (`ns_list`, `ns_forwarding`, `ns_connected_v4`, `ns_nft_json`, `ns_conntrack_has`, `bond_mode`, `ns_tc_has_mirred`, `dnsmasq_lease_in_range`, `chrony_synced`, `lldp_neighbor`, `link_rx_bytes`, `retry`, …). |
| `test-lab-1-routing-failover.sh` | Lab 1 — ECMP route / metric failover |
| `test-lab-2-acl-stateful.sh` | Lab 2 — nft forward chain + capture |
| `test-lab-3-vlan-trunk.sh` | Lab 3 — VLAN-aware bridge trunk |
| `test-lab-4-bonding.sh` | Lab 4 — active-backup + 802.3ad bond |
| `test-lab-5-nat-pat.sh` | Lab 5 — masquerade + DNAT |
| `test-lab-6-mirror-span.sh` | Lab 6 — tc mirred port mirror |
| `test-lab-7-dhcp.sh` | Lab 7 — dnsmasq server + dhcrelay |
| `test-lab-8-vrf-rpf.sh` | Lab 8 — VRF isolation + rp_filter |
| `test-lab-9-arp-proxyarp.sh` | Lab 9 — PERMANENT neigh + proxy ARP |
| `test-lab-10-mtu-pmtu.sh` | Lab 10 — MTU + PMTU cache |
| `test-lab-11-services.sh` | Lab 11 — chrony + rsyslog + lldp |
| `test-lab-12-appliance.sh` | Lab 12 — full appliance + health sweep |
