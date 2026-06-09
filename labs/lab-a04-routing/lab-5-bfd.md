# Lab A04 — Lab 5: BFD-Accelerated Failover

Pairs with: [Article 4 §5a](../../wiki/article-04-routing-daemons.md#bfd-with-frr)

Return to [Lab A04 README](./README.md) for setup instructions. Requires Lab 4 (BGP unnumbered) to be complete.

## What this section teaches

Wire BFD to the BGP sessions from Lab 4 and measure the failover-time improvement. BFD sends sub-second keepalives independently of the routing protocol; when it detects a failure, it notifies BGP immediately rather than waiting for BGP's holdtime timer (90 seconds by default) to expire.

```mermaid
graph LR
    bfdd["bfdd\n(sub-second keepalives)"]
    bgpd["bgpd\n(session state)"]
    kernel["kernel FIB\n(route install/remove)"]
    bfdd -->|"peer down → notify"| bgpd
    bgpd -->|"session down → withdraw routes"| kernel
```

## Build the topology

BGP unnumbered from Lab 4 must be running. Verify:

```bash
ip netns exec r1 vtysh -N r1 -c 'show ip bgp summary'   # should show Established
```

## Part A — Add BFD to BGP neighbors

Configure r1:

```bash
/lab/frrvtysh r1
r1# configure terminal
r1(config)# router bgp 65001
r1(config-router)# neighbor r1-r2 bfd
r1(config-router)# end
r1# configure terminal
r1(config)# bfd
r1(config-bfd)# profile fast-detect
r1(config-bfd-profile)# receive-interval 100
r1(config-bfd-profile)# transmit-interval 100
r1(config-bfd-profile)# detect-multiplier 3
r1(config-bfd-profile)# exit
r1(config-bfd)# peer r1-r2 interface r1-r2
r1(config-bfd-peer)# profile fast-detect
r1(config-bfd-peer)# end
r1# write
r1# exit
```

Configure r2:

```bash
/lab/frrvtysh r2
r2# configure terminal
r2(config)# router bgp 65002
r2(config-router)# neighbor r2-r1 bfd
r2(config-router)# neighbor r2-r3 bfd
r2(config-router)# end
r2# configure terminal
r2(config)# bfd
r2(config-bfd)# peer r2-r1 interface r2-r1
r2(config-bfd-peer)# receive-interval 100
r2(config-bfd-peer)# transmit-interval 100
r2(config-bfd-peer)# detect-multiplier 3
r2(config-bfd-peer)# end
r2# write
r2# exit
```

Do the same for the r2↔r3 link on both r2 and r3.

## Part B — Verify BFD peers are Up

```bash
ip netns exec r1 vtysh -N r1 -c 'show bfd peers'
```

Look for `Status: up`. BFD should be Up within a few seconds of configuration (it does not wait for BGP).

```bash
# BFD shows which BGP sessions it is protecting
ip netns exec r1 vtysh -N r1 -c 'show bgp neighbors r1-r2' | grep -A 5 'BFD'
```

## Part C — Measure failover without BFD (optional baseline)

Before BFD was added, BGP's holdtime was 90 seconds. If you removed BFD now and flapped the link, you would wait up to 90 seconds for the route to disappear from the FIB. With BFD, it should be sub-second.

**The timing exercise (reader exercise — not automated):**

Open two shells. In shell 1, poll the route continuously:

```bash
# Shell 1: poll until route disappears, then reappears
while true; do
    result=$(ip -n r1 route show 10.0.0.3/32 proto bgp 2>/dev/null)
    ts=$(date +%T.%N | cut -c1-12)
    echo "$ts: ${result:-NO ROUTE}"
    sleep 0.1
done
```

In shell 2, flap the link:

```bash
# Shell 2: flap and time it
ip link set r1-r2 down
sleep 3
ip link set r1-r2 up
```

Watch shell 1. The route should disappear within about 300ms (3 × 100ms BFD interval) and reappear once BGP reconverges after the link comes back. Note the timestamps.

For comparison, remove BFD (`no neighbor r1-r2 bfd`), repeat the exercise, and observe the 90-second disappearance window.

## Test your work

```bash
./tests/routing/test.sh 5
```

The checker confirms: BFD peer Up, TX interval ≤ 300ms, routing session references BFD. It does not flap anything.

## Comprehension questions

<details>
<summary>Answers (click to expand)</summary>

**Q: BFD detected the link failure in 300ms. My BGP session took 5 seconds to drop. What is happening?**
A: BFD detection (300ms) is fast, but there is still overhead in the notification chain: BFD notifies bgpd, bgpd withdraws routes and sends NOTIFY to the peer, zebra receives the withdraw and removes the route from the FIB. Each step takes a few milliseconds but the chain is correct. If it consistently takes 5 seconds, check whether `bfdd` is actually running in the namespace and whether the BFD peer is Up *before* the flap.

**Q: What is the `detect-multiplier`?**
A: The detection time = `transmit-interval × detect-multiplier`. With 100ms TX and multiplier 3, the detection time is 300ms. The multiplier exists to tolerate packet loss — if one BFD packet is lost but the peer is still alive, we wait for 3 missed packets before declaring the peer down.

**Q: Does BFD protect OSPF as well as BGP?**
A: Yes. Add `ip ospf bfd` under the interface configuration in OSPF mode: `interface r1-r2 / ip ospf bfd`. BFD then monitors the OSPF neighbor independently of OSPF's dead-interval (40 seconds by default). The failover improvement is the same.

</details>

## Teardown

No teardown needed. The BFD config persists for Lab 6.

---

Next: [Lab 6 — Persisting FRR](./lab-6-persistence.md)
