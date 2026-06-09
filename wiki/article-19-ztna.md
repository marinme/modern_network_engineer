---
type: topic
tags: [article-plan, modern-architectures, ztna, identity, ai-intro]
article_number: 19
cluster: Modern Network Architectures
created: 2026-05-28
updated: 2026-05-28
sources: [[[network-engineer-modernization-series]]]
related: [[[zero-trust-network-access]], [[openziti]], [[legacy-config-coverage-map]]]
status: draft
---

# Article 19 — Zero Trust Network Access (ZTNA)

The article that introduces the model replacing traditional VPN in enterprise environments. Network engineers need both the conceptual model and the mechanics, and Article 18 gives them both with a working open-source ZTNA system.

## Expected outcome

The reader finishes the article able to:

- Articulate the ZTNA model: identity-driven, policy-based, default-deny — and contrast it credibly with VPN.
- Build a working ZTNA system from open-source components ([[openziti]]) with identity, posture, and policy in one place.
- Evaluate commercial ZTNA vendors against the open-source equivalent.
- Recognize **identity-and-policy as the natural answer to "what is the agent allowed to do"** — the framing the rest of the series' agentic workflows benefit from.

## Outline

1. **Why this article exists.** VPN is being replaced. ZTNA is the replacement; understanding both the model and the mechanics is now table stakes.
2. **The model.** Identity-driven (the actor, not the network location, is the unit of trust). Policy-based (access is granted per service, per identity, per posture). Default-deny (no implicit trust; every connection is authorized).
3. **The contrast with VPN.** What VPN gave you (network access) versus what ZTNA gives you (service access). Why the perimeter model failed.
4. **Identity, posture, policy — the three vocabulary words.** Each defined concretely with the OpenZiti equivalents.
5. **OpenZiti as the lab vehicle.** Edge routers, identities, services, policies. The minimum architecture.
6. **Lab walkthrough.** Stand up OpenZiti. Create two identities. Expose a service running in containerlab. Write a policy granting one identity access, denying the other. Test both. Add a posture check; re-test.
7. **Reading commercial ZTNA through this lens.** The shape of vendor offerings (Zscaler, Cloudflare, Twingate, Tailscale). What's the same; what's bundled differently.
8. **How LLM agents fit here.** Agents as identities under policy — the first introduction of this concept and where it lives in the curriculum.

## Lab

Reader builds an OpenZiti ZTNA overlay:

1. Stands up a Ziti controller and at least one edge router locally.
2. Defines two identities ("alice", "bob") with their respective tokens.
3. Exposes a service running in a [[containerlab]] node — e.g., the NetBox UI or an Arista cEOS eAPI endpoint.
4. Writes a policy granting `alice` access to the service; `bob` is implicitly denied.
5. Connects as each identity from the Ziti client; verifies access matches policy.
6. Adds a posture check (e.g., requires a particular OS); re-tests.

## Foundational material needed

| Prerequisite | Covered where | Notes |
|---|---|---|
| Linux | **[[article-01-linux-for-network-engineers]]** | |
| Docker | **[[article-11-docker]]** | OpenZiti components run in containers |
| Containerlab | **[[article-12-containerlab]]** | Service-host topology |
| API basics | **[[article-10-rest-apis]]** | OpenZiti is configured via API |
| Identity / PKI concepts | **External** — light treatment in the article | Reader gets enough to be useful, pointed at deeper material |

## Assumed networking knowledge

External prerequisites the reader brings in. See [[assumed-networking-knowledge]] for the series-wide picture.

- Traditional VPN architecture (remote-access and site-to-site) and the perimeter model
- The "network location = trust" failure mode as something the reader has seen first-hand
- PKI, certificates, and certificate-based identity at concept level
- Posture assessment / device health checks
- Service-based vs network-based access as a category split
- Commercial ZTNA vendors as context: Zscaler, Cloudflare Access, Twingate, Tailscale
- Default-deny firewalling

## How LLM agents fit here

This is the article that introduces **agents as identities under policy**. Up through Article 17, agentic guardrails have been mostly environmental: a sandbox, a dry-run gate, a Git audit trail. Article 18 adds a complementary mechanism: the agent has its own identity, policy decides what that identity is allowed to reach, and the policy is enforced by the network itself rather than by the application or the orchestrator.

The teaching: **the ZTNA model is the right answer to "what is the agent allowed to do."** An agent operating against the reader's network should not have unbounded access; it should have an identity (call it `agent-network-readonly` or `agent-config-applier`), a policy attached to that identity, and posture requirements that determine when the identity is valid. Every action the agent takes traverses an edge router that checks the policy before letting the connection through. This is the same model the reader is now applying to human users, applied to non-human ones.

Two patterns the article should teach:

- **Scoping the agent's reach.** A read-only agent for diagnostics gets one identity with access only to eAPI `show` endpoints. A change-applier agent for [[article-13-terraform]] gets a different identity with broader access, *and* a more stringent posture requirement (e.g., only valid when invoked from CI, not from a developer laptop). Different jobs, different identities, different policies. The article walks through this concretely with two OpenZiti policies.
- **Revocation as a first-class operation.** If an agent misbehaves, identity-and-policy gives the reader a clean off-switch — revoke the identity, the agent loses access immediately, no infrastructure change required. This is the operational answer to "what if the agent goes wrong" that environmental sandboxing alone doesn't provide.

The forward-looking note for the article: **[[article-23-mcp]]'s MCP server should be exposed through ZTNA, not on a flat network.** The MCP server is itself a service; the AI assistant connecting to it is an identity; the policy controls which tools the assistant can invoke. The reader who has built the Article 18 lab has built the substrate the capstone agent deserves to run on.

A useful additional framing the article can drop in: **identity-and-policy composes with the earlier guardrails, it doesn't replace them.** The sandbox bounds the blast radius; the dry-run gates the apply; the audit trail records the history; the identity-and-policy decides what the agent can even *reach*. Each layer addresses a different failure mode.

## Concepts and entities introduced

- [[zero-trust-network-access]] (deepened from stub)
- [[openziti]] (deepened from stub)

## Open questions

_(none yet)_
