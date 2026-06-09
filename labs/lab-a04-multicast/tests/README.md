# Lab A04 Multicast — verification tests

Automated checkers for [Lab A04 — Multicast](../README.md).

## Running

From inside the workbench container (tests mounted at `/lab/tests/multicast/`):

```bash
./tests/multicast/test.sh          # list available parts
./tests/multicast/test.sh 1        # verify FRR pimd PIM-SM
./tests/multicast/test.sh 2        # verify smcroute static mroute
```

Exit `0` all-pass, `1` a check failed, `2` setup error or unknown part.

## Design principles

- **Verify-only / non-destructive.** Scripts check state from the live kernel and FRR. No iperf streams are started by the checker (the streaming exercise is in the walkthrough).
- **Auto-discovering.** Discovers the router namespace by checking for `mc_forwarding=1` and an active multicast forwarding socket.
- **Objective + mechanism.** Checks both that traffic could flow (IGMP group joined, (S,G) entry present) and that the mechanism is correct (PIM enabled on both interfaces, FRR `pimd` vs `smcroute` active).

## Files

| File | Purpose |
|------|---------|
| `test.sh` | Dispatcher |
| `lib.sh` | Shared helpers |
| `test-lab-1-pim-sm.sh` | FRR pimd — mc_forwarding on, PIM on both interfaces, IGMP group joined, (S,G) entry present |
| `test-lab-2-smcroute-static.sh` | smcroute — static (S,G) in kernel mroute, no pimd running |
