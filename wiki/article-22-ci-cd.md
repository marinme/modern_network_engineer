
# Article 22 — CI/CD for Network Changes

The article that replaces change-management meetings with pipelines. Network changes have historically been manual, error-prone, and reviewed in rooms; CI/CD applies the developer model — automated testing, peer review, repeatable deployment — to network configuration.

## Expected outcome

The reader finishes the article able to:

- Build a CI/CD pipeline for network changes: PR triggers [[containerlab]] spin-up, tests run against the proposed config, merge gated on results.
- Understand which tests matter at which stages (lint, unit, integration, post-deploy verification).
- Introduce the model to their own team with a defensible argument.
- Recognize CI/CD as the **manager-reviewer multi-agent workflow** the rest of the series' agentic patterns compose into.

## Outline

1. **Why this article exists.** Change windows and manual reviews scale badly. CI/CD scales. The path through is not optional for any organization growing past a small operations team.
2. **The pipeline shape.** PR opens → lint → unit tests → spin up containerlab → integration tests against the lab → review → merge → deploy → post-deploy verification → close.
3. **Lint and unit tests.** YAML validity, schema compliance (back to Article 6), syntactic correctness of generated configs. Cheap, fast, run on every push.
4. **Integration tests in a lab.** This is the interesting part. The proposed config is applied to a [[containerlab]] topology; tests run against the live state (BGP comes up, expected reachability holds, no unexpected drops). The lab is ephemeral per-pipeline-run.
5. **Review etiquette in a CI-gated world.** What humans look at when machines have already approved structure and basic correctness. The intent layer.
6. **Deployment to "real" environments.** Staging → production gating. Approval gates. Rollback strategies.
7. **Post-deploy verification.** Tying telemetry from [[article-21-observability]] back into the pipeline. The deploy is not "done" until metrics say so.
8. **Lab walkthrough.** A full pipeline: GitHub Actions or GitLab CI, a sample network-configs repo, all of the above stages working.
9. **How LLM agents fit here.** Manager/reviewer multi-agent patterns in full — the composition article for the agentic curriculum.

## Lab

Reader builds:

1. A `network-configs` repository with [[ansible]] playbooks targeting a [[containerlab]] topology.
2. A CI workflow ([[github-actions]] or [[gitlab-ci]]) that on every PR:
   - Lints the YAML.
   - Validates inventory against a schema.
   - Brings up containerlab.
   - Runs `ansible-playbook --check` against the lab.
   - Applies it; runs verification tests (reachability, BGP, drift against intended state).
   - Tears down the lab.
   - Reports back to the PR.
3. A merge requiring all checks to pass plus one approval.
4. (Stretch) A post-deploy step that queries Prometheus from [[article-21-observability]] to verify the change had its intended observable effect.

## Foundational material needed

| Prerequisite | Covered where | Notes |
|---|---|---|
| Git, PR workflow | **[[article-06-git]]** | The article is a Git workflow extended |
| YAML, JSON, schemas | **[[article-07-structured-data]]** | Tests use schemas |
| Python (for test harnesses) | **[[article-08-python]]** | The custom verification tests are Python |
| Ansible (the playbooks being tested) | **[[article-09-ansible]]** | |
| eAPI/REST (for verification) | **[[article-10-rest-apis]]** | |
| Docker | **[[article-11-docker]]** | CI runners are containers |
| Containerlab | **[[article-12-containerlab]]** | Lab platform inside the pipeline |
| Telemetry for post-deploy verification | **[[article-21-observability]]** | The closing brace |

By Article 21 the pipeline composes most of the series. This is the dress rehearsal for [[article-23-mcp]] and the credible production pattern the reader can take to their team.

## Assumed networking knowledge

External prerequisites the reader brings in. See [[assumed-networking-knowledge]] for the series-wide picture.

- Change management and change windows as the legacy practice
- Staging vs production environments as a real distinction
- Rollback as an operational concept (not just `copy start run`)
- The expectation that BGP adjacency, reachability, and config drift can be tested programmatically
- VLAN and policy changes as canonical example change types
- Pre- and post-deploy verification as a discipline

## How LLM agents fit here

This is the article where the **manager/reviewer multi-agent workflow** lands in full. Every earlier article has hinted at this — agents propose, humans approve, sandboxes verify, telemetry confirms — and Article 21 is where the shape becomes formal. CI/CD is, after all, already a manager-reviewer-gate workflow built for humans. Agents just take some of the seats.

The teaching: **a pipeline is the orchestration layer where multiple agents and humans collaborate at well-defined seams.** The article should name the seams and assign roles:

- **The author seat** — a human, or an agent, opens a PR with the proposed change. If an agent, the prompt provided to it grounds in [[article-14-netbox]] SoT and references the intent in a structured form. The agent's output is the PR itself: the change, the test additions if any, the rollback plan in the description.
- **The reviewer seat** — a second LLM, intentionally adversarial, reads the diff and the test results and pushes back. Reviewer-pattern in the strict sense: a different prompt, a different model instance, no shared context with the author. The reviewer's job is to find what the author missed — security concerns, blast-radius issues, missing test cases.
- **The gate seat** — the pipeline itself. Deterministic. Lint passes, schema validates, lab integration tests pass, post-deploy verification succeeds. No LLM here; the pipeline is the closed-form arbiter of merge-readiness. This is the *guardrail* of the workflow — the same idea from [[article-12-containerlab]] composed into a sequence.
- **The approver seat** — a human, always. The human reviews after the machines have done their work, with the diff, the test output, the reviewer's notes, and the post-deploy plan all in one view. The human's job has changed: less syntax checking, more intent judgment.

This is **the full agentic workflow pattern for network operations**. Article 21 is where the reader should leave with a clear mental model of *who does what*, and that mental model is reused — with different actors filling the seats — for the rest of the reader's career.

Three concrete patterns to teach:

- **Author + reviewer as separate prompts to separate model instances.** Same model, separate contexts. The reviewer should never have seen the author's reasoning; only the artifact. This is a real, implementable workflow — the article shows the GitHub Actions YAML that orchestrates it.
- **Test generation as an agentic task.** When a PR adds a new feature (new VLAN, new policy), the agent can propose the new tests alongside the change. The pipeline runs them; the reviewer agent checks they're adequate. Reader approves the bundle.
- **Failure-driven prompting.** When a test fails, the failure output becomes the next prompt automatically — feeding back into the author agent with "this test failed, here's the output, propose a fix." This is the closed-loop agentic CI/CD pattern; the article should be honest that fully autonomous closed loops are still rare in production but increasingly tractable in sandboxes.

The forward-looking note: **[[article-23-mcp]] is the article that asks "what if the agent's tools are richer than `kubectl apply`?" — and the answer is the same workflow with more powerful actors in the seats.** Article 21 establishes the workflow; Article 22 explores how far it can extend.

## Concepts and entities introduced

- [[ci-cd-for-network-changes]] (deepened from stub)
- [[github-actions]] (deepened from stub)
- [[gitlab-ci]] (deepened from stub)

## Open questions

_(none yet)_
