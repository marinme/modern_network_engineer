---
type: topic
tags: [article-plan, infrastructure-as-code, netbox, source-of-truth, ai-intro]
article_number: 14
cluster: Infrastructure as Code
created: 2026-05-28
updated: 2026-05-28
sources: [[[network-engineer-modernization-series]]]
related: [[[netbox]], [[nautobot]], [[source-of-truth]], [[legacy-config-coverage-map]]]
status: draft
---

# Article 14 — NetBox as Source of Truth

The inflection-point article. Treating the network as data, with a single authoritative source, is what separates "automating tasks" from "automated network."

## Expected outcome

The reader finishes the article able to:

- Understand why source of truth matters operationally — not just philosophically.
- Model their own network in [[netbox]]: sites, devices, interfaces, IPAM, custom fields.
- Build automations driven by NetBox data instead of static inventory files.
- Recognize **the SoT as the agent's grounding context** — the thing that stops an agent from hallucinating topology.

## Outline

1. **Why this article exists.** The inflection point. Quote: "Treating the network as data, with a single authoritative source, is the inflection point between 'automating tasks' and 'automated network.'"
2. **The mental model.** SoT-as-database. Reality should match SoT; when it doesn't, *something is wrong* — and the disagreement is itself operational signal.
3. **NetBox data model tour.** Sites, racks, devices, device types, interfaces, IP addresses, prefixes, VLANs, custom fields. Just enough to map the reader's own network.
4. **Running NetBox locally.** Docker Compose, persistence, getting to a working UI in five minutes.
5. **Populating NetBox from a [[containerlab]] topology.** Either via the API directly or via a small Python ingester. The reader sees the data flow.
6. **Driving Ansible from NetBox.** The NetBox dynamic inventory plugin. An Ansible playbook whose inventory comes from NetBox instead of a static file. Change a value in NetBox; re-run the playbook; see the change propagate.
7. **[[nautobot]] briefly.** The fork's positioning. Why it might be the right answer in some shops.
8. **Drift: when reality and SoT disagree.** Detection patterns. Reconciliation patterns. The decision: update SoT to match reality, or update reality to match SoT, or escalate.
9. **Lab walkthrough.** End to end: containerlab up → ingest topology into NetBox → drive a playbook from NetBox data → break something → detect drift → reconcile.
10. **How LLM agents fit here.** Grounding via SoT, and drift reconciliation as the first reviewer-pattern primer.

## Lab

Reader:

1. Spins up NetBox locally with Docker Compose.
2. Deploys the containerlab topology from Article 11.
3. Runs a Python script that walks the topology and creates the corresponding NetBox objects (sites, devices, interfaces, IPs).
4. Runs an Ansible playbook with NetBox as dynamic inventory; pushes interface descriptions populated from NetBox custom fields.
5. Manually changes a description on one device.
6. Runs a drift-detection script (extension of the Article 9 drift detector) that compares device-reported state against NetBox.
7. Reconciles by updating NetBox; reruns the playbook; verifies parity.

## Foundational material needed

| Prerequisite | Covered where | Notes |
|---|---|---|
| Linux, shell | **[[article-01-linux-for-network-engineers]]** | |
| Git | **[[article-06-git]]** | |
| YAML/JSON | **[[article-07-structured-data]]** | NetBox API speaks JSON |
| Python | **[[article-08-python]]** | The ingester is Python |
| Ansible (dynamic inventory) | **[[article-09-ansible]]** | The playbook portion of the lab |
| REST APIs | **[[article-10-rest-apis]]** | Reader hits the NetBox API the same way they hit eAPI |
| Docker | **[[article-11-docker]]** | NetBox runs via Docker Compose |
| Containerlab | **[[article-12-containerlab]]** | Source topology for the ingest |
| `q-nautobot-vs-netbox-choice` | **Open question** | The article needs to take a position; the open question on the wiki tracks this |

By Article 13 the prerequisite list is large because the article is genuinely a composition point. It's the first article where the *whole stack so far* gets used at once.

## Assumed networking knowledge

External prerequisites the reader brings in. See [[assumed-networking-knowledge]] for the series-wide picture.

- DCIM concepts: sites, racks, devices, device types
- IPAM: prefixes, IP addresses, VLANs
- Interface modeling: cabling, MAC addresses, descriptions
- Custom fields / metadata on network objects (the muscle memory of "we tag devices with X")
- Running config vs intended config (drift)
- VLAN-to-VNI mapping
- Dynamic vs static inventory as a mental model
- Network segmentation groups as data, not as switch config

## How LLM agents fit here

This is the article that introduces **prompt grounding** in operational terms. Up through Article 12, the agent's inputs were mostly the reader's prompts. From Article 13 on, the agent has access to authoritative network data — the SoT — and the article needs to teach the reader why this changes what the agent is good for and how to prompt it.

The teaching: **an agent without ground truth hallucinates topology; an agent with NetBox in its context proposes against the network you actually have.** This is mechanical, not magic. When the agent's prompt includes "here is the relevant NetBox data: {dump}" the agent's output is constrained by that data in ways that prompts-from-memory aren't. The reader should leave Article 13 understanding that *the quality of an agent's network reasoning is bounded above by the quality of the SoT it has access to* — which incidentally is also the quality bound for human reasoning, but humans had years to learn workarounds.

Two patterns the article should teach:

- **SoT-in-context prompts.** A bad prompt is "add a new leaf to my fabric." A good prompt is "given this NetBox dump showing two spines and three leaves and the IP scheme below, propose the NetBox object diff to add a fourth leaf consistent with the existing pattern." The agent's output is now checkable against the dump it was given. The pattern transfers cleanly to Ansible playbook prompts, Terraform module prompts, and eventually MCP tool calls.
- **Drift reconciliation as a reviewer-pattern primer.** This is the article's most underrated unlock. The reader writes a drift-detection script that compares device reality with NetBox. When it disagrees, *something is wrong* — but which side? The reader sees two roles emerge naturally: one agent (or one Ansible run) proposes that NetBox should be updated to match reality; another agent (or the reader, or a CI gate) reviews whether that's actually the correct reconciliation, or whether reality should be reverted to match SoT. The article doesn't have to call this "multi-agent reviewer pattern" out loud, but the shape is there for [[article-22-ci-cd]] to formalize.

The forward-looking note worth dropping in the article: **almost every meaningful agentic workflow in [[article-23-mcp]] starts with an SoT query.** The MCP server exposes "what does NetBox say about device X" as a tool, the agent calls it before proposing any change, and the change is reviewed against the SoT-grounded plan. Article 13 is where the SoT becomes the agent's first dependency.

## Concepts and entities introduced

- [[netbox]]
- [[nautobot]]
- [[source-of-truth]]

## Open questions

- [[q-nautobot-vs-netbox-choice]] — the article needs to take a position; open question tracks this
