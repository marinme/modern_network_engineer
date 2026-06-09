---
type: topic
tags: [article-plan, modern-architectures, vxlan, evpn, ai-callback]
article_number: 17
cluster: Modern Network Architectures
created: 2026-05-28
updated: 2026-05-28
sources: [[[network-engineer-modernization-series]]]
related: [[[vxlan]], [[evpn]], [[overlay-network]], [[arista-ceos]], [[legacy-config-coverage-map]]]
status: draft
---

# Article 17 — Overlay Networks: VXLAN and EVPN Fundamentals

The article that demystifies the fabric protocols underpinning almost every modern network — data center, campus, SD-WAN, cloud. A network engineer who treats VXLAN/EVPN as black magic is locked out of design conversations for the next decade.

## Expected outcome

The reader finishes the article able to:

- Read and reason about an EVPN-VXLAN fabric: VTEPs, VNIs, route types, RD/RT.
- Troubleshoot common fabric issues using the same `tcpdump` + `show` skills they've sharpened across the series.
- Participate credibly in fabric design conversations.
- Recognize where today's LLM agents are weak (protocol design, dense-spec reasoning) and where they're strong (config generation, troubleshooting from logs).

## Outline

1. **Why this article exists.** EVPN-VXLAN is the lingua franca of modern fabrics. Black-box understanding is no longer acceptable.
2. **VXLAN encapsulation.** The frame on the wire. The VTEP. The VNI. Why L2-over-L3 was the solution to the scaling problem.
3. **EVPN as a control plane.** BGP carrying MAC and IP reachability. Why BGP — what it solved that flood-and-learn didn't.
4. **Route types that matter in practice.** Type 2 (MAC/IP), Type 3 (Inclusive Multicast), Type 5 (IP Prefix). Skim the rest.
5. **RD and RT, the bits everyone gets confused on.** Worked example with concrete values.
6. **What happens when a host comes online.** End-to-end walkthrough: host MAC learned, EVPN Type-2 originated, remote VTEPs install, traffic flows.
7. **Troubleshooting patterns.** `show bgp evpn summary`. `show vxlan vtep`. `show mac address-table`. The minimal set.
8. **Lab walkthrough.** A working EVPN-VXLAN fabric in [[containerlab]] with [[arista-ceos]]: two spines, two leaves, two hosts on different leaves talking over the fabric.
9. **How LLM agents fit here.** Callback noting where current agents are honestly weak.

## Lab

Reader brings up a containerlab topology:

1. Spine-leaf with two spines, two leaves, BGP underlay.
2. iBGP EVPN address family between leaves (route-reflected through spines, or full mesh).
3. One VLAN/VNI stretched across both leaves.
4. Hosts attached to each leaf in that VLAN.
5. Reader verifies ping host-to-host across the fabric.
6. Reader walks the EVPN tables (`show bgp evpn`) to see the Type-2 entries.
7. (Optional) Adds a Type-5 prefix and observes inter-VNI routing.

The keepable artifact is a working fabric topology in Git.

## Foundational material needed

| Prerequisite | Covered where | Notes |
|---|---|---|
| Linux/`tcpdump` for the wire view | **[[article-01-linux-for-network-engineers]]** | |
| Containerlab | **[[article-12-containerlab]]** | The fabric runs here |
| BGP fundamentals | **External** — assumed from existing background | The article does not teach BGP |
| Familiarity with cEOS CLI/eAPI | **[[article-10-rest-apis]]** | Helpful but not strictly required |
| L2/L3 fabric concepts | **External** — assumed from existing background | |

A callback article in the agentic arc. The networking content is dense; the agentic content is deliberately light.

## Assumed networking knowledge

External prerequisites the reader brings in. This is the **densest prereq cliff in the series** — BGP including address families is explicitly external. See [[assumed-networking-knowledge]].

- BGP fundamentals including address families (explicitly external)
- L2 vs L3 forwarding distinction
- Flood-and-learn MAC learning
- Spine-leaf / Clos design
- Route reflectors, or full-mesh iBGP as the alternative
- MAC address tables (`show mac address-table` muscle memory)
- VLAN as an L2 broadcast domain
- Encapsulation and tunneling generally as a mental tool
- Underlay vs overlay distinction
- Multicast at concept level (implicit in EVPN Type-3 Inclusive Multicast routes)
- Inter-VRF / inter-VNI routing
- Vendor RD/RT conventions and why they exist

## How LLM agents fit here

A **callback** article, and the place to set an expectation honestly: **today's LLM agents are at their weakest with dense protocol design and at their strongest with config generation and troubleshooting against real signal.** Article 16 lets the reader see both edges of that, because the article has both.

Where the agent is weak here: novel protocol design conversations. "Design a fabric for this site with these constraints" gets answers that read fluent but include subtle inaccuracies — wrong route type for the use case, wrong RD/RT convention for the vendor, wrong best-current-practice for the year. The reader is better than the agent at this *because* they have the experiential intuition the agent lacks. The article should be honest about this: agents do not yet replace the engineer in the design seat.

Where the agent is strong here:

- **Config generation given a known pattern.** "Configure leaf-1 as a VTEP in VNI 10010 with these neighbors and these mappings." The agent produces correct config because the pattern is well-documented and the variables are well-specified. Verification happens in the lab — apply the config, watch `show bgp evpn summary` come up.
- **Troubleshooting from output.** Reader runs `show bgp evpn summary`, pastes it with the symptom ("host on leaf-1 can't reach host on leaf-2 in the same VNI"); agent reads the output, proposes hypotheses ("Type-2 not being originated by leaf-1; check `evpn` instance mapping"), reader verifies. This is where agents earn their keep on a fabric.

The skill-versus-agent decision from [[article-09-ansible]] applies here in a sharper form: **the fabric configuration template is a skill (an [[ansible]] role); the diagnostic walk is an agent loop.** The reader should be coached to treat these as different tools and reach for each at the right moment.

No new agentic concept is introduced; this article cements the honest-about-capabilities posture that the capstones ([[article-23-mcp]] and [[article-24-aiops-ibn]]) will return to.

## Concepts and entities introduced

- [[vxlan]] (deepened from stub)
- [[evpn]] (deepened from stub)
- [[overlay-network]] (deepened from stub)

## Open questions

_(none yet)_
