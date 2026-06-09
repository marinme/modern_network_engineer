---
type: topic
tags: [article-plan, infrastructure-as-code, terraform, opentofu, ai-intro]
article_number: 13
cluster: Infrastructure as Code
created: 2026-05-28
updated: 2026-05-28
sources: [[[network-engineer-modernization-series]]]
related: [[[terraform]], [[opentofu]], [[infrastructure-as-code]], [[declarative-vs-imperative]]]
status: draft
---

# Article 13 — Terraform / OpenTofu for Network Infrastructure

The article that introduces declarative provisioning as how modern infrastructure is built. Network engineers need to read and write it; Article 12 teaches enough to do both.

## Expected outcome

The reader finishes the article able to:

- Read existing Terraform code without panic.
- Write simple modules that provision network infrastructure declaratively.
- Articulate when declarative provisioning is the right tool versus configuration management ([[ansible]]).
- Recognize **`plan` as the canonical dry-run guardrail** — and connect that pattern to every later approval gate in the series.

## Outline

1. **Why this article exists.** Provisioning is a category distinct from configuration management. Terraform is the dominant tool; the reader should not be locked out of conversations that use it.
2. **The mental model.** Providers, resources, state, plans. Declarative target state ("this fabric exists") versus imperative steps ("create this, then that").
3. **Declarative vs imperative, made concrete.** Same outcome (a leaf switch with three interfaces configured) expressed in Ansible and in Terraform. Side-by-side comparison. The reader sees the tools as complements, not substitutes.
4. **The `plan` / `apply` rhythm.** What `plan` shows. What `apply` actually does. Why `plan` is the most important Terraform feature for operational safety.
5. **State, the topic engineers always struggle with.** What it is, where it lives, what corruption looks like, remote state for teams.
6. **Modules.** Reusable, parameterized infrastructure. The shape of a good module versus a bad one.
7. **OpenTofu briefly.** Why the fork exists. When the reader should care.
8. **Lab walkthrough.** Provision an [[arista-ceos]] topology declaratively (using a community provider or a `local-exec` driving [[containerlab]]). Watch `plan`. Apply. Change a value. Watch `plan` again. Apply. Destroy. Re-apply. Same result.
9. **How LLM agents fit here.** `plan` as the dry-run gate; the article where the agent's proposals start to look like reviewable diffs.

## Lab

Reader builds a small Terraform configuration that:

1. Declares a [[containerlab]] topology as data (number of spines, number of leaves, IP scheme).
2. Renders config files for each device from templates.
3. Optionally drives `containerlab deploy` via `local-exec` or a community provider.
4. Reader runs `terraform plan`, reads the diff, applies. Changes the spine count, runs `plan` again, sees exactly what will change.

The keepable artifact: a parameterized lab topology the reader can stamp out at any size.

## Foundational material needed

| Prerequisite | Covered where | Notes |
|---|---|---|
| Linux fluency | **[[article-01-linux-for-network-engineers]]** | |
| Git | **[[article-06-git]]** | Terraform code lives in a repo |
| YAML/HCL fluency | **[[article-07-structured-data]]** | HCL is close enough to YAML that Article 6 transfers; the article notes the differences |
| Ansible for the contrast | **[[article-09-ansible]]** | Critical — the declarative/imperative distinction is taught against Article 8 |
| A lab platform | **[[article-12-containerlab]]** | Terraform provisions into containerlab; reader has just finished Article 11 |
| [[declarative-vs-imperative]] mental model | Foreshadowed in Article 8, deepened here | |

## Assumed networking knowledge

External prerequisites the reader brings in. See [[assumed-networking-knowledge]] for the series-wide picture.

- "Provisioning" vs "configuration management" as a category distinction the reader can recognize once named
- Leaf switch with interfaces (the cross-tool worked example)
- IP scheme design for a spine-leaf topology
- Routes as the surface where surprises show up ("the plan added a route I didn't ask for")

## How LLM agents fit here

Terraform is the article that introduces **`plan` as the literal embodiment of the dry-run guardrail**. The pattern the rest of the series has been hinting at — agent proposes, human reviews the diff, human approves the apply — is exactly what `terraform plan` does, built into the tool. Article 12 is where the reader sees the gate is not a special bolt-on for AI workflows; it's the same gate human engineers have been using all along, now with an LLM as one of the proposers.

The teaching: **`plan` is what makes Terraform safe to let an agent drive.** An LLM can write Terraform with reasonable fluency; `terraform plan` then renders, in unambiguous terms, what the LLM's code would actually do. Resources to be created. Resources to be destroyed. Attributes to be changed. The diff is mechanical, deterministic, and reviewable in the same way a Git diff is reviewable. The reader's role is exactly the role they had in [[article-06-git]] reviewing a teammate's PR — except the teammate this time may be an agent, and the diff is a Terraform plan instead of a code diff.

This unlocks a workflow pattern worth naming clearly in the article: **agent writes, `plan` shows, human approves, `apply` runs.** The agent never invokes `apply` directly in this article — only in [[article-23-mcp]] does that become a possibility, and even there only under explicit approval gates. The reader internalizes the rhythm here, where the tool's own design enforces it.

Two concrete moves for the article:

- **Module generation with verification.** Hand the agent a description of a target topology and the provider's schema; it produces an HCL module; the reader runs `terraform init && terraform plan` and reads the output. If the plan does what the description asked for, the reader applies. If it doesn't, the plan output *is* the next prompt: "the plan added a route I didn't ask for, fix the module."
- **State as an explanation surface.** State is the topic engineers get confused on, and an LLM that can explain `terraform state list` and `terraform state show` output in context — *"why does this resource think it already exists?"* — saves real time. The reader runs the commands, the agent reads the output and explains.

The forward-looking note: the `plan` pattern recurs at every layer of the rest of the series. [[article-14-netbox]]'s drift reconciliation is a `plan`-like diff between SoT and reality. [[article-22-ci-cd]]'s pipeline gates are `plan`-like checks the pipeline enforces. [[article-23-mcp]]'s gated remediation is `plan`-like in spirit even when the underlying tool isn't Terraform. Article 12 is where this pattern stops being theoretical and gets a name.

## Concepts and entities introduced

- [[terraform]]
- [[opentofu]]
- [[infrastructure-as-code]]
- [[declarative-vs-imperative]] (deepened from Article 8)

## Open questions

_(none yet)_
