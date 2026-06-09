
# Article 24 — Where This Is Heading: AIOps and Intent-Based Networking

A synthesis article. Less hands-on, more strategic. Connects every prior topic to the trajectory of the industry. Honest about hype versus reality. Grounds predictions in the concrete capabilities the reader now has.

## Expected outcome

The reader finishes the article with:

- A strategic map of where the industry is heading: [[aiops]] and [[intent-based-networking]] as labels for two overlapping trajectories.
- A clear-eyed understanding of which vendor claims are real, which are hype, and which are real-but-narrower-than-presented.
- Their own position on that map.
- A learning agenda for the next 12–18 months, with concrete projects and reading recommendations.

## Outline

1. **Why this article exists, and what it deliberately is not.** Not a lab article. Not a vendor evaluation guide. A strategic synthesis grounded in the working competence the reader has just built.
2. **AIOps, the term.** What vendors mean. What "AIOps" actually covers when stripped of marketing — anomaly detection, log clustering, alert correlation, incident similarity. Where each is real-and-useful, where each is hype.
3. **Intent-based networking, the term.** What vendors mean. The honest version: a compiler from intent specification to declarative configuration, grounded in SoT, validated in a lab, deployed via CI/CD, verified by telemetry. Which is — pointedly — what the reader has just built across Articles 13–22.
4. **The IBN compiler is the agent.** This is the reframing the article is built around. The "compiler" in IBN marketing is, in 2026 practice, a constrained agent. The reader knows how to build constrained agents now.
5. **The honest timeline.** What's deployable today, narrowly. What's deployable in 1–2 years, more broadly. What's still research-grade. What's marketing.
6. **The reader's position on the map.** They've built every layer. They can build more. They can also evaluate vendors who claim to have built it already. The article is about confidence calibration as much as it is about technology.
7. **A 12-month learning agenda.** Recommended reading. Recommended open-source projects to contribute to or extend. Recommended communities. Possibly a follow-on series the author has in mind.
8. **How LLM agents fit here.** Honest-about-hype, plus the reframing of prompt-as-intent.

## Lab

No lab. Article 23 is intentionally a stepping-back article. The "exercise" is the reader writing their own 12-month learning agenda based on the recommendations.

## Foundational material needed

| Prerequisite | Covered where | Notes |
|---|---|---|
| The entire series | **[[article-01-linux-for-network-engineers]] through [[article-23-mcp]]** | Article 23 is synthesis; every prior article informs it |

This is the only article in the series with no external prerequisites and no new technology to introduce. The prerequisite *is* the curriculum.

## Assumed networking knowledge

External prerequisites the reader brings in. The final article — assumes the operational stack the series just built. See [[assumed-networking-knowledge]].

- AIOps as a vendor category and the standard claims (anomaly detection, log clustering, alert correlation, incident similarity)
- Intent-based networking as a vendor category and the standard claims
- Self-driving-network marketing claims at a familiar-enough level to push back on
- The full operational stack the curriculum has just built: source of truth → applier → sandbox → telemetry → pipeline → agent
- Capacity forecasting as a distinct analytical class
- Familiarity with what each prior article in the series produced

## How LLM agents fit here

Article 23's agentic content is twofold: **honest-about-hype**, and the reframing of **prompt-as-intent at scale**.

**Honest-about-hype.** The reader has now seen, end to end, what LLM agents can do well in network operations and what they can't. The article should pin down the line:

- **Real, usable today (2026):** translator/explainer (every article), code generation with verification ([[article-08-python]]), playbook/template generation ([[article-09-ansible]]), tool-using agents under structured guardrails ([[article-23-mcp]]), anomaly correlation against recent changes ([[article-21-observability]]), troubleshooting from structured output ([[article-17-vxlan-evpn]], [[article-20-kubernetes-networking]]).
- **Real but narrow:** sandboxed change proposal with human-approved apply, narrowly-scoped autonomous remediation for well-defined failure modes.
- **Largely hype today:** broadly autonomous network operations, vendor "self-driving network" claims, IBN systems that genuinely close the loop without a human in it.
- **Genuine ML, separately from LLMs:** statistical anomaly detection, log clustering, capacity forecasting — these are real and useful, and the reader should distinguish them from LLM-driven work, because they have different deployment profiles.

The reader's job in any vendor evaluation is now to ask, on each claim: *which bucket above does this actually fall into?* They have the experiential basis to answer.

**Prompt-as-intent at scale.** [[intent-based-networking]]'s pitch is that an operator expresses intent and the system reconciles configuration to match. Stripped of vendor language, this is exactly the prompt → tool-use → verification loop the reader has built. The IBN "compiler" is, in practical 2026 terms, an LLM agent with access to SoT, applier tools, and telemetry — exactly the architecture from [[article-23-mcp]].

This means **the reader's MCP-driven setup is a working IBN system on a small scale**, and the gap between what they have and what vendors sell is mostly: more tools, more scale, more polish, more domain-specific RAG over the operator's network. Not a different kind of system.

The article should leave the reader with one piece of confidence and one piece of caution:

- **Confidence:** they can build, evaluate, and lead the adoption of every layer they've seen. They are not behind the industry; they are inside it.
- **Caution:** the technology is moving fast enough that one year of treating-it-as-static is enough to be left behind. The learning agenda matters.

The forward-looking note: **the series is a foundation, not a finish line. The author intends to write follow-up material on harder topics — multi-vendor fabric automation at scale, AI-driven incident response, agentic security operations — that picks up where Article 23 leaves off.** The reader who completed this curriculum is exactly the audience for that.

## Concepts and entities introduced

- [[aiops]] (deepened from stub)
- [[intent-based-networking]] (deepened from stub)

## Open questions

_(none yet)_
