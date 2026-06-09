
# Article 23 — AI Agents and MCP for Network Operations (capstone)

The capstone the rest of the series prepares the reader for. Model Context Protocol lets AI assistants interact with real systems through structured interfaces. Network operations is a natural fit — query device state, propose changes, execute under guardrails. The article covers the integration story and the critical question of when and where to trust AI with production changes.

## Expected outcome

The reader finishes the article able to:

- Build and operate AI-integrated network tooling on top of [[model-context-protocol]].
- Hold a defensible position on what to automate and what to gate, anchored in the specific tools, guardrails, and patterns established earlier in the series.
- Lead AI adoption discussions in their own organization without overstating or understating current capabilities.

## Outline

1. **Why this article exists.** Every prior article has been making this possible. Article 22 is where the reader composes the patterns into a working, agent-driven network operation.
2. **What MCP actually is.** A protocol for an AI assistant to call external tools through structured interfaces. Server (exposes tools) and client (the assistant). Tools have typed schemas, authentication, scope.
3. **Designing tools for an MCP server.** Pulling forward [[article-10-rest-apis]]'s tool-design principles — read/write separation, structured I/O, explicit scope. Each device API becomes a candidate tool; each operation becomes a candidate tool definition.
4. **Composing the substrate.** [[containerlab]] as the sandbox, [[netbox]] as the SoT, [[ansible]] / [[terraform]] as the applier, [[prometheus]] as the sensor. Each becomes a tool surface for the MCP server. The reader sees the entire series stack as one system.
5. **Agentic workflow patterns inside MCP.** Inspection-only mode. Plan-then-apply mode with human approval. The manager/reviewer pattern from [[article-22-ci-cd]] reframed with MCP tools.
6. **When and where to trust the agent.** The decision framework: blast radius, reversibility, verification surface. Where current models are reliable enough to act without approval, where they aren't, and how to tell the difference for a given operation.
7. **Lab walkthrough.** The MCP server lab build.
8. **The honest frontier.** Where this all is in 2026: working sandbox demos, narrow production deployments, broad organizational anxiety. What the next 18 months will likely bring.
9. **How LLM agents fit here.** This article *is* the agentic article; the entire body is the "how AI fits" treatment.

## Lab

Reader builds a simple MCP server exposing a [[containerlab]] topology:

1. Tools (read-only): `list_devices`, `get_device_state(device)`, `get_running_config(device)`, `query_netbox(filter)`, `query_prometheus(query)`.
2. Tools (write, gated): `propose_config_change(device, change)` — does not apply, only stages and runs through dry-run; returns a diff for human approval. `apply_approved_change(approval_token)` — applies a previously-staged change only with a valid token.
3. An AI assistant (Claude Desktop or another MCP-capable client) connects and is asked to diagnose a deliberately broken adjacency.
4. The assistant uses the read-only tools to identify the issue, proposes a fix via `propose_config_change`, the reader reviews the proposed diff and either approves (releasing the token) or rejects.
5. (Stretch) The post-deploy verification step queries Prometheus to confirm the fix landed.

The lab is the keepable working artifact — the reader leaves with an actual MCP-driven network operation they can demo and extend.

## Foundational material needed

| Prerequisite | Covered where | Notes |
|---|---|---|
| Python | **[[article-08-python]]** | MCP servers are typically Python |
| REST APIs and tool design | **[[article-10-rest-apis]]** | The direct ancestor of MCP tool design |
| Docker | **[[article-11-docker]]** | MCP server runs in a container |
| Containerlab | **[[article-12-containerlab]]** | Sandbox layer |
| NetBox SoT | **[[article-14-netbox]]** | Grounding layer |
| ZTNA / identity-and-policy | **[[article-19-ztna]]** | The MCP server should be exposed under ZTNA; the agent is an identity |
| Observability | **[[article-21-observability]]** | Post-deploy verification |
| CI/CD multi-agent workflow | **[[article-22-ci-cd]]** | The MCP workflow is the same pattern in a different shape |

By Article 22 every earlier article is in play. This is the capstone the curriculum was built to reach.

## Assumed networking knowledge

External prerequisites the reader brings in. This is the capstone — it composes the entire prior stack and assumes you have done each piece by hand. See [[assumed-networking-knowledge]].

- The read-vs-write split on device operations and why it matters for safety
- BGP adjacency as the canonical "broken thing to diagnose"
- Config diff as a reviewable artifact (carried from [[article-06-git]])
- Device hostname and scope parameters as the dispatch axes
- Blast radius and reversibility as operational risk categories
- Concrete examples of irreversible actions: certificate revocation, route-leak risk, default-route changes
- "Diagnose a broken adjacency" workflow fluency — the reader should have done this dozens of times by hand
- Everything carried from Articles 9, 20, 21 (APIs, telemetry, CI/CD)

## How LLM agents fit here

Article 22 is the agentic article; its entire content is the "how AI fits" treatment. Rather than introducing a new agentic concept, it **composes every earlier one into a working agent-driven system**, and the article's job is to make that composition concrete and inspectable.

The four pillars established earlier all show up here:

- **Tools are the boundary** ([[article-10-rest-apis]]). Every MCP tool is a structured, read/write-separated, scope-bounded interface. The agent's affordances are exactly what the server exposes; the design of the server is the design of what the agent can do.
- **The environment is the guardrail** ([[article-12-containerlab]] + [[article-16-localstack]]). Agent-driven actions land in a containerlab or a staging environment first. The promotion to production is a human decision, every time, until trust is earned for narrow operations.
- **The SoT is the grounding** ([[article-14-netbox]]). The first thing the agent does, on essentially every task, is consult NetBox. Without grounding, the agent hallucinates topology. With grounding, the agent's reasoning is constrained to the network the reader actually operates.
- **The pipeline pattern composes** ([[article-22-ci-cd]]). The author/reviewer/gate/approver seats from Article 21 are exactly the seats in an MCP-driven operation. MCP doesn't replace the pattern; it gives the agent richer tools to fill its seat.

The article should then **name the decision framework** for trusting agentic actions:

- **Blast radius.** What's the worst case if the action is wrong? Bounded blast radius (a single device in a sandbox; a read-only query against production) tolerates more automation. Unbounded blast radius (a fabric-wide config push) requires human approval until further notice.
- **Reversibility.** Can the action be undone cheaply? A reversible action ([[article-13-terraform]] `apply` against a sandbox; a NetBox value change with an audit trail) tolerates more automation. An irreversible action (anything touching production identity, certificate revocation, route-leak risk) does not.
- **Verification surface.** Can the action's effect be checked automatically? An action with a clean telemetry-anchored verification ([[article-21-observability]]) tolerates more automation. An action whose verification requires human judgment (a policy intent change) does not.

The honest position the article should take: **today (2026), the right place to deploy MCP-driven agents in network operations is read-only diagnostic work and sandboxed change proposal with human-approved apply. That envelope will expand — but every expansion should be earned by accumulated track record of correct behavior in a narrower envelope first.** The article is explicit that *the curriculum produces an engineer capable of evaluating that expansion responsibly*, not an engineer chasing the maximally autonomous setup.

The lab's design embodies this: the agent diagnoses freely, proposes freely, and applies only with an approval token released by the human reading the proposed diff. This is the working artifact the reader carries forward — a system that's actually useful today and that extends gracefully as trust accumulates.

A useful pointer to forward: **the agent's tools should be exposed through [[article-19-ztna]] identity-and-policy.** Agent gets an identity; identity is policy-bound; revocation is one operation. The Article 18 substrate is the operational home for the Article 22 agent.

## Concepts and entities introduced

- [[model-context-protocol]] (deepened — the capstone subject)

## Open questions

_(none yet)_
