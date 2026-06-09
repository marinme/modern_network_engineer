# Lab A02 — verification tests

Automated checkers for the [Lab A02 topology labs](../README.md). They run **after** you
build a sub-lab inside the [`containers/article-02`](../../../containers/article-02/)
workbench and confirm the finished topology actually meets the lab's objective.

This lab is multi-part (five sub-labs sharing one container), so the standard entrypoint
`test.sh` takes the part you want to verify.

## Running

The compose workbench mounts this directory read-only at `/lab/tests`, so from the
`root@workbench:/lab#` prompt, pass the part you built — by number, slug, or name:

```bash
./tests/test.sh 1          # Lab 1 (also: ./tests/test.sh 1-router  or  router)
./tests/test.sh            # list the parts
```

(The per-part scripts, e.g. `./tests/test-lab-1-router.sh`, still run directly if you
prefer.) If you started the container with the raw `docker run` command (not compose), add
`-v "$(pwd)/labs/lab-a02-topologies/tests:/lab/tests:ro"` to that command first.

Exit status is `0` if every check passed, `1` if any check failed, `2` on a setup error or
an unknown part (e.g. a required tool missing — run it inside the container, which has them
all).

## Design principles

- **Verify-only / non-destructive.** The scripts only *read* state (`ip … show`,
  `sysctl -n`, `ip route get`), send `ping`, and sniff passively with `tcpdump`. They
  never create, delete, or reconfigure a namespace, address, route, or sysctl. Safe to run
  against a topology you built by hand; safe to re-run.
- **Auto-discovery, not hard-coded names.** Each script discovers the namespace names and
  IP addresses you actually used from the live kernel state, identifies the roles by
  topology shape (e.g. "the router is the namespace that forwards and has two subnets"),
  and tests those. Rename `h1` → `alice` or re-IP to `192.168.x` and the test still passes.
- **Check the objective and the mechanism.** A test asserts the *specified reachability*
  (e.g. host A reaches host B) **and** that it happens via the *specified mechanism* (the
  flow transits the router, proven by `tcpdump` on both legs) — so a same-subnet shortcut
  can't earn a green check.

## Layout

| File | Purpose |
|------|---------|
| `test.sh` | **Standard entrypoint.** `test.sh <part>` dispatches to the per-part checker (by number, slug, or name); `test.sh` with no argument lists the parts. Derives the part list from the `test-lab-*.sh` files, so it stays correct as sub-labs are added. |
| `lib.sh` | Shared helpers: `pass`/`fail`/`summary`/`finish`, `require_cmds`, and read-only namespace/bridge/VLAN introspection (`ns_list`, `ns_forwarding`, `ns_connected_v4`, `ns_route_nexthop`, `ns_bridges`, `ns_bridge_ports`, `ns_vlan_filtering`, `ns_iface_kind`, `ns_iface_mac`, `fdb_has_mac`, `port_vlans`, `tcpdump_*`). Sourced by every test. |
| `test-lab-1-router.sh` | Lab 1 — `host — router — host`: forwarding on, host routing via the router, end-to-end ping, transit proven on both router legs. |
| `test-lab-2-switch.sh` | Lab 2 — bridge with host ports: same-subnet L2 reachability, and MAC learning in the bridge `fdb`. |
| `test-lab-3-compose.sh` | Lab 3 — `host—switch—router—switch—host`: same-subnet on-link L2 vs. cross-subnet routing, transit proven on both router legs. |
| `test-lab-4-svi.sh` | Lab 4 — VLAN-aware bridge with SVIs: vlan-filtering + vlan-type gateways, same-VLAN L2, and inter-VLAN routing proven on both SVIs. |
| `test-lab-5-trunk.sh` | Lab 5 — two VLAN bridges + trunk: same-VLAN reachability across the trunk with distinct 802.1Q tags, and cross-VLAN isolation. |

All five follow the same shape: source `lib.sh`, discover the topology from live state, then
assert the lab's specified reachability *and* its mechanism.

## Requirements

Bash 4+, plus `ip` (iproute2), `jq`, `tcpdump`, `ping`, `timeout`, `awk`, `grep` — all
present in the article-02 container. The scripts need the same capabilities the labs do
(`NET_ADMIN`/`NET_RAW`/`SYS_ADMIN`), which the workbench already grants.
