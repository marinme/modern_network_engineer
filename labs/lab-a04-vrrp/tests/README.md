# Lab A04 VRRP — verification tests

Automated checkers for [Lab A04 — VRRP](../README.md). Run **after** building a sub-lab inside the [`containers/article-04`](../../../containers/article-04/) workbench.

## Running

From inside the workbench container (tests mounted at `/lab/tests/vrrp/`):

```bash
./tests/vrrp/test.sh          # list available parts
./tests/vrrp/test.sh 1        # verify keepalived VRRP
./tests/vrrp/test.sh 2        # verify FRR vrrpd
```

Exit `0` all-pass, `1` a check failed, `2` setup error or unknown part.

## Design principles

- **Verify-only / non-destructive.** Scripts discover what you built and check state. They never kill a keepalived process, change priorities, or cause a failover.
- **Auto-discovering.** Scripts find the MASTER by reading `ip -j addr` — the namespace that currently has the VIP assigned.
- **Objective + mechanism.** Checks that the VIP is on the correct interface AND that VRRP advertisements are being sent.

## Files

| File | Purpose |
|------|---------|
| `test.sh` | Dispatcher |
| `lib.sh` | Shared helpers (same as routing lab) |
| `test-lab-1-keepalived.sh` | keepalived VRRP — VIP on MASTER, VRRP ads visible, ping to VIP works |
| `test-lab-2-frr-vrrpd.sh` | FRR vrrpd — `show vrrp` shows MASTER/BACKUP, VIP on correct namespace |
