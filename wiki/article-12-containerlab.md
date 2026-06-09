---
type: topic
tags: [article-plan, modern-device-interaction, containerlab, lab, ai-intro]
article_number: 12
cluster: Modern Device Interaction
created: 2026-05-28
updated: 2026-05-28
sources: [[[network-engineer-modernization-series]]]
related: [[[containerlab]], [[arista-ceos]], [[docker]], [[legacy-config-coverage-map]]]
status: draft
---

# Article 12 — Containerlab Deep Dive

The dedicated deep-dive on the lab platform underpinning most of the series. After Article 11 the reader can build, share, and version realistic network labs as code — and has the workflow they'll use for every future learning topic.

## Expected outcome

The reader finishes the article able to:

- Author a [[containerlab]] topology from scratch and bring it up reproducibly.
- Version a lab in Git, share it with a teammate, and run it identically on another machine.
- Integrate a lab into a CI pipeline so labs become tests (preview of Article 21).
- Understand containerlab as **the agent's sandbox** — the structural property that makes everything from Article 12 onward safe to automate.

## Outline

1. **Why this article exists.** Containerlab is what makes the rest of the series cheap, fast, and safe. Without it (or something like it), every lab requires real hardware and every agentic experiment requires real blast radius.
2. **Topology files.** YAML structure: nodes, links, kinds, defaults. Worked example: a 4-node Clos fabric (2 spines, 2 leaves) in cEOS.
3. **Multi-vendor support.** Brief survey: cEOS, SR Linux, Junos cRPD, Nokia, FRR. Why the series defaults to cEOS.
4. **Bringing it up, tearing it down.** `containerlab deploy`, `containerlab destroy`, `containerlab inspect`. The two-command working loop.
5. **Connecting from outside.** Exposed management ports, SSH, eAPI from the host, mapping container names to topology positions.
6. **Patterns for sharing labs as code.** Topology in Git, configs as files, startup-config injection. The lab *is* the repo.
7. **CI integration preview.** A topology brought up in GitHub Actions or GitLab CI; tests run against it; teardown on completion. Full treatment in [[article-22-ci-cd]].
8. **Lab walkthrough.** Build a realistic multi-node topology, push initial configs, verify adjacencies, commit, tear down, redeploy from Git, confirm bit-identical results.
9. **How LLM agents fit here.** The sandbox-first guardrail pattern in full.

## Lab

Reader authors and commits a lab repository containing:

1. A `topology.clab.yml` file with a 4-node EVPN-VXLAN-ready fabric (spines + leaves, hosts attached).
2. A `configs/` directory with per-device startup configs.
3. A `Makefile` or shell script with `deploy`, `destroy`, `redeploy` targets.
4. A `README.md` documenting how to bring up the lab.

Reader brings the lab up, verifies the topology, intentionally breaks one node's config, observes the symptom, fixes via redeploy, commits the fix.

## Foundational material needed

| Prerequisite | Covered where | Notes |
|---|---|---|
| Linux fluency | **[[article-01-linux-for-network-engineers]]** | |
| Git | **[[article-06-git]]** | The lab is a repo |
| YAML fluency | **[[article-07-structured-data]]** | Topology files are YAML |
| Docker | **[[article-11-docker]]** | Containerlab is Docker underneath; reader understands what's happening when nodes start |
| Arista cEOS image | **External** — free from Arista with registration | One-time setup; the article points the reader at the download |
| API/playbook fluency | **[[article-09-ansible]]** + **[[article-10-rest-apis]]** | Useful for pushing configs into the lab; not strictly required for the topology itself |

This is the article every later article quietly assumes. Article 11 is also the *forward dependency* that Articles 7, 8, and 9 (Python, Ansible, REST APIs) referenced — by the time the reader gets here, they've already used containerlab through a pre-packaged harness, and Article 11 is where the harness comes apart.

## Assumed networking knowledge

External prerequisites the reader brings in. This is the first article where the **BGP cliff** begins; a reader weak on BGP fundamentals will struggle from here on. See [[assumed-networking-knowledge]].

- Spine-leaf / Clos fabric topology — named without explanation from here forward
- BGP fundamentals: sessions, neighbors, `Established` state, iBGP
- EVPN-VXLAN as the target fabric type (named here; taught in [[article-17-vxlan-evpn]])
- Management vs data interfaces on a network device
- Startup-config injection model (vendor-style boot-time config)
- Multi-vendor awareness: cEOS, SR Linux, Junos cRPD, Nokia, FRR
- Device adjacencies as a verification target — "neighbor X should be Established"

## How LLM agents fit here

Containerlab is the article where the agent's hands come off the table-edge and onto the keyboard — but only because the keyboard is wired to a sandbox that costs nothing to destroy. This is the dedicated home in the series for **sandbox-first guardrails**: the principle that an agent's blast radius should be limited by where it can act, not by how carefully it's been prompted. Every later article that lets an agent *do* something assumes a containerlab (or its equivalent) sitting underneath.

The core idea is structural, not behavioral. A guardrail is not "tell the agent to be careful" — that is a wish, not a control. A guardrail is **a property of the environment that makes a class of mistakes harmless or impossible.** Containerlab provides several at once: the topology is ephemeral (a bad change is undone by `containerlab destroy && containerlab deploy`), the YAML topology file is version-controlled (you can see exactly what the agent built), and the entire fabric is isolated from any production network. An agent given shell access to a containerlab can issue every wrong command in the textbook and the worst outcome is a re-deploy.

This unlocks a workflow pattern the rest of the series leans on heavily: **propose-in-sandbox, verify, then promote**. The reader's job — the orchestration job — is to define what "verified" means before the agent starts. For a config change, verification is a passing test inside the lab. For a topology change, verification is the lab coming up cleanly with expected adjacencies. The agent is allowed to iterate freely inside the loop because the loop has a hard outer boundary. The human picks the goal, picks the verification, and decides whether the verified artifact is allowed to leave the lab.

The pedagogical reason to formalize this here, rather than in [[article-22-ci-cd]] where the full pattern lands, is that the reader needs to internalize *why* sandboxes matter before they meet a pipeline that depends on one. CI/CD is the manager-reviewer workflow built on top; containerlab is the floor the workflow stands on. A later callback in [[article-16-localstack]] reuses the same principle for cloud APIs, and [[article-22-ci-cd]] composes containerlab into the full reviewer-and-gates pattern.

A concrete first exercise inside the article: hand the agent a containerlab topology and the task "add a leaf switch with iBGP to both spines and verify adjacency comes up." Let it edit the YAML, redeploy, check `show bgp summary`, iterate until both neighbors are `Established`. The reader watches, intervenes when the agent goes sideways, and at the end has both a working topology *and* the diff that produced it — two artifacts, both reviewable. That is the shape of every agentic loop in the rest of the series.

## Concepts and entities introduced

- [[containerlab]] (deep dive on the concept page)
- [[arista-ceos]] (deepened from earlier stub mentions)

## Open questions

_(none yet)_
