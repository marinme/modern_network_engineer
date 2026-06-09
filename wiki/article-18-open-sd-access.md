
# Article 18 — Open-Source SD-Access Lab (flagship)

The most ambitious lab in the series. Cisco's SD-Access is a specific product, but the *pattern* — fabric plus source of truth plus policy plus orchestration — is what matters for the next decade of campus networking. Article 17 builds something conceptually equivalent using open-source tools.

## Expected outcome

The reader finishes the article able to:

- Articulate the pattern Cisco SD-Access implements: fabric + SoT + policy + orchestration.
- Build a working open-source campus fabric: EVPN-VXLAN on [[arista-ceos]], [[netbox]] (or [[nautobot]]) as SoT, [[ansible]] for orchestration, policy enforcement at the fabric edge.
- Evaluate commercial fabric offerings critically against the open-source equivalent.
- See multiple earlier-article patterns compose into one working system.

## Outline

1. **Why this article exists.** The pattern matters more than the product. The reader builds the pattern in open-source to understand commercial offerings on their own terms.
2. **The SD-Access pattern, deconstructed.** Four layers: fabric (data plane), control (EVPN), source of truth (intent), orchestration (intent → reality). Each layer mapped to a tool the reader has already met.
3. **Architecture walkthrough.** Spine-leaf EVPN-VXLAN fabric; NetBox/Nautobot modeling devices, fabric topology, VLANs, security groups; Ansible reconciling fabric state from SoT; edge policy (ACLs or segmentation) driven from SoT custom fields.
4. **Building it.** Start with the fabric from Article 16. Add SoT modeling from Article 13. Add Ansible reconciliation from Article 8. Add edge policy as SoT-driven config.
5. **Reading commercial SD-Access through this lens.** What Cisco offers as a managed product, what the reader has now built. Where the commercial offering's value is real (scale, support, GUI), where the open-source equivalent is more transparent (every layer is inspectable code).
6. **Lab walkthrough.** End-to-end build, by far the longest in the series. The article assumes substantial reader time.
7. **How LLM agents fit here.** Callback-and-compose — every earlier agentic pattern reused at once.

## Lab

The flagship lab. Reader builds:

1. A 4-node EVPN-VXLAN fabric in [[containerlab]] (from Article 16).
2. NetBox locally with the fabric modeled completely: devices, interfaces, VLANs/VNIs, segmentation groups as custom fields.
3. An Ansible playbook that reconciles fabric configuration from NetBox: bring up a new VLAN by adding it in NetBox, watching it propagate to all relevant VTEPs.
4. An edge policy layer: NetBox custom fields define a host's group; Ansible renders ACLs on the leaf the host attaches to.
5. End-to-end demo: add a new host to NetBox in group X; run the playbook; host is reachable to other group X members and blocked from group Y members.

This is a working, demoable open-source campus fabric.

## Foundational material needed

| Prerequisite | Covered where | Notes |
|---|---|---|
| Linux | **[[article-01-linux-for-network-engineers]]** | |
| Git | **[[article-06-git]]** | |
| YAML/JSON | **[[article-07-structured-data]]** | |
| Ansible | **[[article-09-ansible]]** | Orchestration layer |
| REST APIs / eAPI | **[[article-10-rest-apis]]** | For inspection |
| Containerlab | **[[article-12-containerlab]]** | Lab platform |
| NetBox | **[[article-14-netbox]]** | SoT layer |
| EVPN-VXLAN | **[[article-17-vxlan-evpn]]** | Fabric layer |
| Resolution of [[q-nautobot-vs-netbox-choice]] | **Open question** | This article needs a position on NetBox vs Nautobot |

By Article 17 every prior article in the series is in play. This is the deliberate compositional payoff of the curriculum.

## Assumed networking knowledge

External prerequisites the reader brings in. This article composes nearly every prior layer of the series; weak prereqs from earlier articles compound here. See [[assumed-networking-knowledge]].

- Cisco SD-Access at concept level — the campus-fabric product class
- Edge ACLs / policy enforcement at the leaf
- Segmentation and micro-segmentation as a campus pattern
- Host onboarding / 802.1X-style host-to-group mapping
- Group-based policy ("allow group X to group Y") as a mental model
- Campus fabric vs data-center fabric distinction
- Multi-layer campus design (access / distribution / core) as the legacy world this replaces
- Everything carried from [[article-17-vxlan-evpn]] (BGP-EVPN, VXLAN, VRF)

## How LLM agents fit here

A **callback-and-compose** article. No new agentic concept is introduced; the article is where multiple earlier patterns operate together for the first time, and the agentic value is in seeing how they stack:

- **The SoT is the agent's grounding** (from [[article-14-netbox]]). Every agent prompt about the fabric starts with a NetBox dump.
- **The Ansible playbook is the codified skill** (from [[article-09-ansible]]). Reconciling SoT to reality is a fixed runbook — agents don't write it, they invoke it.
- **The containerlab is the sandbox** (from [[article-12-containerlab]]). Every proposed change is validated there before any real-world equivalent gets considered.
- **The fabric config templates are agent-generated** (from [[article-17-vxlan-evpn]]). The agent is strong here; verification is the lab coming up.
- **Diffs are reviewable** (from [[article-06-git]] and [[article-13-terraform]]). Every change — SoT, playbook output, fabric config — terminates in a Git diff a human can approve.

The article should make this stack visible. The reader is no longer learning a single agentic move; they are seeing the composition of moves they've already learned into a system. This is the rehearsal for [[article-22-ci-cd]] (where the composition gets formalized into a pipeline) and [[article-23-mcp]] (where the composition gets exposed as a coherent agent surface).

One specific exercise worth including: ask the agent to **author the change in a single end-to-end pass** — "add a new segment X with hosts a, b, c; here's the NetBox dump; here's the playbook; produce the NetBox object diff and the expected playbook output, and tell me what to verify in the lab." The reader applies the NetBox diff, runs the playbook, runs the verification. The agent's output spans every layer; the reader's verification spans every layer; the agentic loop is now operating at the system level, not a single tool.

A useful honest note for the article: **this is the upper bound of what a single-shot prompt can reliably do today, and it's still verification-heavy.** Pushing beyond this — agents running unsupervised across multiple layers — is the territory [[article-23-mcp]] and [[article-24-aiops-ibn]] map and bound.

## Concepts and entities introduced

- [[cisco-sd-access]] (deepened — the comparison subject)
- No new concept pages otherwise; this article is composition, not introduction

## Open questions

- [[q-nautobot-vs-netbox-choice]] — must be resolved for this article's lab to be concrete
