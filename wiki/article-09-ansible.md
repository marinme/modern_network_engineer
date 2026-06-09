---
type: topic
tags: [article-plan, automation-primer, ansible, ai-intro]
article_number: 9
cluster: Automation Primer
created: 2026-05-28
updated: 2026-05-28
sources: [[[network-engineer-modernization-series]]]
related: [[[ansible]], [[jinja2]], [[arista-ceos]]]
status: draft
---

# Article 09 — Ansible Primer

Same framing as Article 7 — a primer that establishes shape and vocabulary, not a deep dive into a tool with thousands of pages of existing documentation.

## Expected outcome

The reader finishes the article able to:

- Understand Ansible's mental model: declarative state, idempotency, inventory as data.
- Read existing playbooks confidently and run them safely.
- Write simple playbooks against Arista cEOS via the `eos_` module family.
- Recognize the productive division between *playbooks* (codified procedures) and *agents* (judgment loops), and apply the distinction in their own work.

## Outline

1. **Why this article exists, and what it deliberately is not.** Same posture as Article 7 — enough Ansible to be effective and to know when to reach for it.
2. **The mental model.** Declarative state ("interface X should be configured like this") versus imperative scripting ("run this command"). Idempotency: running a playbook twice produces the same end state.
3. **Inventory as data.** The connection back to [[yaml]] and the foreshadowing of [[netbox]] in Article 13. Static inventory now, dynamic inventory later.
4. **Playbooks, plays, tasks, handlers.** The minimum useful vocabulary. One worked example explained line by line.
5. **Variables, facts, and `vars_files`.** How data flows into a playbook.
6. **[[jinja2]] templating.** The minimum needed to render a config from variables. Loops, conditionals, filters.
7. **The `eos_` module family.** What's available, what to reach for, where vendor-specific knowledge matters.
8. **Lab walkthrough.** A playbook that pushes a small config change to a cEOS container — first idempotency check, second change, then a deliberate "config drift" to show how the playbook reconciles.
9. **How LLM agents fit here.** Skill versus agent: a playbook *is* the canonical codified skill. The decision rule introduced here is reused for the rest of the series.

## Lab

Reader is given:

1. A small cEOS container topology (from the lab harness; full treatment in Article 11).
2. A starter inventory file and a starter playbook.

Reader:

1. Runs the playbook, observes idempotency on the second run.
2. Adds a task to set an interface description from a variable.
3. Uses a Jinja2 template to render a small banner.
4. Drifts the config manually on the device, reruns the playbook, watches Ansible reconcile.

## Foundational material needed

| Prerequisite | Covered where | Notes |
|---|---|---|
| Linux fluency | **[[article-01-linux-for-network-engineers]]** | |
| Git workflow | **[[article-06-git]]** | Playbooks live in a repo |
| YAML fluency | **[[article-07-structured-data]]** | Playbooks and inventory are YAML; this is non-negotiable |
| Python basics | **[[article-08-python]]** | Reader installs Ansible into a virtualenv; understands what `pip install ansible` is doing |
| A cEOS lab | **[[article-12-containerlab]]** — *not yet covered* | Article 8 uses a pre-packaged lab harness; Article 11 unpacks it |
| Declarative-vs-imperative mental model | **[[declarative-vs-imperative]]** + cross-reference to **[[article-13-terraform]]** | Introduced here; deepened in Article 12 |

The reader is using a lab harness whose internals come in Article 11. That's intentional — Ansible is taught before the lab platform because Ansible's *concepts* don't require lab fluency, only lab availability.

## Assumed networking knowledge

External prerequisites the reader brings in. See [[assumed-networking-knowledge]] for the series-wide picture.

- Concept of "pushing config" to a device and the change-window habits around it
- Banners, interface descriptions, VLAN-level config — the surface area where small declarative changes happen
- What an Arista (or any vendor) running-config looks like
- Vendor-to-vendor config-syntax variation as a real cost
- Config drift as an operational concept (declarative reconciliation is framed against this)

## How LLM agents fit here

This is the article where the reader meets the **skill-versus-agent decision** for the first time, because Ansible is the canonical codified-skill tool. A playbook is what a fixed runbook looks like when you commit it to disk: declarative, idempotent, reviewable, replayable. The reader needs to leave Article 8 with a sharp rule for when to reach for a playbook and when an LLM agent would be the wrong tool — and vice versa.

The rule: **if you can write the runbook in advance, write the playbook. If the runbook would have to branch on what you find, you need an agent.** Provisioning a new leaf with a known template is a playbook. Diagnosing why traffic between two specific endpoints is degraded *might* be a playbook for the first three checks and *must* be an agent past that point. The two are complements, not substitutes — the agent's likely output, when faced with a recurring task, is itself a playbook that the agent (or a human) can then run deterministically forever.

The agent's productive role inside the playbook-writing workflow is generation, not execution:

- **Playbook generation.** Given a target state in natural language and the inventory shape, the agent drafts the playbook. The reader runs `ansible-playbook --check` (Ansible's dry-run mode — the same plan/apply idea that [[article-13-terraform]] makes central) and reads the diff before applying. The dry-run *is* the verification gate.
- **Jinja2 template generation.** This is where most engineers get stuck, and where the agent is most useful. Hand it the variable shape and the desired rendered output; it produces a template; the reader renders it against test data and inspects.
- **Reading existing playbooks.** A real production playbook can be hundreds of lines of dense YAML. Asking the agent for a plain-English summary, then verifying claim-by-claim against the source, is faster than reading top-to-bottom for someone still building fluency.

What the agent should *not* do here, yet: run the playbook against real devices. Article 8's loop ends at the dry-run output and the human-approved apply. Article 21 will revisit this in [[article-22-ci-cd]] where the pipeline becomes the gate, and Article 22 in [[article-23-mcp]] where an agent runs the apply itself under structured guardrails. Article 8 deliberately keeps the human's finger on the trigger.

## Concepts and entities introduced

- [[ansible]]
- [[jinja2]]
- [[declarative-vs-imperative]]

## Open questions

_(none yet)_
