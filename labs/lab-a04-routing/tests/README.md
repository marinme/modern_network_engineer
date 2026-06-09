# Lab A04 routing — verification tests

Automated checkers for [Lab A04 — Routing](../README.md). Run **after** building a sub-lab inside the [`containers/article-04`](../../../containers/article-04/) workbench to confirm the finished topology meets the lab's objective.

Lab A04 routing is multi-part (seven sub-labs sharing one container and one `r1—r2—r3` topology), so a single `test.sh` dispatcher takes the part you want to verify.

## Running

From inside the workbench container, the `tests/` directories are mounted read-only at `/lab/tests/`. Run from `/lab`:

```bash
./tests/routing/test.sh          # list available parts
./tests/routing/test.sh 1        # verify Lab 1 (RIB vs FIB)
./tests/routing/test.sh 3        # verify Lab 3 (BGP session)
```

Part numbers, full slugs, and short names all work:

```bash
./tests/routing/test.sh 2              # by number
./tests/routing/test.sh 2-ospf         # by full slug
./tests/routing/test.sh ospf           # by short name
```

Exit `0` if all checks passed, `1` if any check failed, `2` on a setup error (missing binary, FRR not running, or wrong part name).

## Design principles

- **Verify-only / non-destructive.** Scripts never create a namespace, address, route, sysctl, FRR config line, or any other state. They discover what you built and check whether it meets the lab's objective.
- **Auto-discovering.** Scripts find namespaces by role from live kernel and FRR state — the namespace whose FRR has an OSPF adjacency, the one whose BGP RIB has the target prefix. Hard-coded names are avoided.
- **Objective + mechanism.** Each test checks *that* the goal was achieved (e.g. reachability, session Established) *and* that it was achieved *the right way* (e.g. the route's `proto` field says `bgp`, not `static`).
- **Bash only.** No Python, no Go, no external test runners.

## Files

| File | Purpose |
|------|---------|
| `test.sh` | Dispatcher: `test.sh <N>` routes to the right checker. Auto-discovers parts from `test-lab-*.sh` filenames. |
| `lib.sh` | Shared helpers: pass/fail harness, namespace introspection (from A03), and FRR-specific helpers (`frr_ospf_any_full`, `frr_bgp_any_established`, `frr_bfd_peer_up`, `journal_unit_has_entries`, etc.). |
| `test-lab-1-rib-vs-fib.sh` | Lab 1 — FRR socket ready; RIB and FIB both queryable; connected routes consistent |
| `test-lab-2-ospf.sh` | Lab 2 — OSPF neighbor Full; peer loopback as `proto ospf` in FIB |
| `test-lab-3-bgp.sh` | Lab 3 — BGP session Established; prefix in FIB as `proto bgp` |
| `test-lab-4-bgp-unnumbered.sh` | Lab 4 — interface-based peer Established; IPv6 link-local next-hop; IPv4 prefix in FIB |
| `test-lab-5-bfd.sh` | Lab 5 — BFD peer Up; sub-second interval configured |
| `test-lab-6-persistence.sh` | Lab 6 — frr.conf non-empty; router stanza present; config survives daemon restart |
| `test-lab-7-journal-correlation.sh` | Lab 7 — frr@* units have journal entries; kernel entries present; json-pretty query parseable |
