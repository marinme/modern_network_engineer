---
type: topic
tags: [article-plan, operations, observability, streaming-telemetry, prometheus, grafana, ai-intro]
article_number: 21
cluster: Operations and Production
created: 2026-05-28
updated: 2026-05-28
sources: [[[network-engineer-modernization-series]]]
related: [[[streaming-telemetry]], [[prometheus]], [[grafana]], [[gnmi]], [[legacy-config-coverage-map]]]
status: draft
---

# Article 21 — Observability: Metrics, Logs, Streaming Telemetry

The article that retires SNMP polling and syslog grep as the front-line operations toolset. Streaming telemetry plus modern observability stacks are the replacement; Article 20 builds one.

## Expected outcome

The reader finishes the article able to:

- Build a modern observability stack: [[gnmi]] streaming telemetry from cEOS into [[prometheus]], visualized in [[grafana]], alerting on real metrics.
- Articulate the operational shift from pull-based polling to push-based streaming — and why it matters at scale.
- Integrate AI-driven analysis as a sense-making layer over telemetry.
- Recognize **telemetry as the agent's feedback loop** — the third leg of the prompt contract (intent → action → verification).

## Outline

1. **Why this article exists.** SNMP polling has a ceiling; the industry is past it. Streaming telemetry plus the Prometheus/Grafana stack is the floor of modern operations.
2. **Pull vs push.** What SNMP polling actually does. Why polling at the cadence operations needs is expensive. What streaming gets you instead.
3. **gNMI as a streaming protocol.** Subscriptions. Encoded paths. On-change vs sample.
4. **Prometheus and the time-series model.** Metrics, labels, scraping. How a "scrape" maps onto streaming via a gNMI-to-Prometheus collector (e.g., gnmic).
5. **Grafana for visualization.** A useful dashboard's anatomy: interface utilization, BGP session state, packet drops, latency.
6. **Alerting.** What to alert on. What *not* to alert on. The signal-to-noise problem.
7. **Logs alongside metrics.** Brief: structured logs, log aggregation, when logs beat metrics.
7a. **Flow telemetry: NetFlow, sFlow, IPFIX.** What each is, what they tell you that metrics and logs don't (per-flow visibility — who talked to whom, how much), and where they fit in the modern stack (collectors like `nfacctd` / `pmacct` / `goflow2`, often feeding into the same Prometheus/Grafana or into a dedicated flow-analytics store). Recognition only — the lab stays focused on gNMI, but the reader leaves knowing flow telemetry is the third leg alongside metrics and logs.
8. **Lab walkthrough.** Stream gNMI telemetry from a containerlab cEOS topology into Prometheus via gnmic; build a Grafana dashboard with interface counters and BGP state; configure an alert on flapping; deliberately flap a session to trigger it.
9. **How LLM agents fit here.** Closing the feedback loop.

## Lab

Reader:

1. Brings up the [[article-17-vxlan-evpn]] fabric (or any [[containerlab]] topology with BGP).
2. Adds gnmic configured to subscribe to a useful path set (interface counters, BGP neighbor state).
3. Sends those metrics to a local Prometheus.
4. Builds a Grafana dashboard with two panels: interface throughput, BGP session state per neighbor.
5. Adds an alerting rule (BGP state != Established for > 30s).
6. Manually shuts a session; verifies the alert fires; restores; verifies it clears.

## Foundational material needed

| Prerequisite | Covered where | Notes |
|---|---|---|
| Linux | **[[article-01-linux-for-network-engineers]]** | |
| Docker | **[[article-11-docker]]** | Prometheus and Grafana run in containers |
| Containerlab | **[[article-12-containerlab]]** | Lab fabric |
| gNMI familiarity | **[[article-10-rest-apis]]** | Article 9 introduced gNMI; Article 20 puts it to work |
| BGP/EVPN for the lab | **[[article-17-vxlan-evpn]]** | The fabric to instrument |
| YAML | **[[article-07-structured-data]]** | Prometheus and Grafana config are YAML |

## Assumed networking knowledge

External prerequisites the reader brings in. See [[assumed-networking-knowledge]] for the series-wide picture.

- SNMP polling as the legacy operational baseline
- Syslog as the legacy operational baseline
- BGP session state (`Established`, flapping) — the canonical thing to alert on
- Interface counters: `in-octets`, `out-octets`, packet drops, errors
- Latency as a first-class measurable
- Time-series concept: samples, intervals, retention
- Signal-to-noise reasoning about what makes a meaningful alert
- gNMI subscriptions: on-change vs sample modes
- gNMI / YANG encoded paths as a syntax the reader will encounter
- The shape of a useful dashboard (interface utilization, BGP state, drops)

## How LLM agents fit here

This is where the **feedback loop** finally closes. Up through Article 19, an agent could propose, the reader (or a CI gate) could approve, and the apply could land — but verifying that the apply *actually achieved what was intended* required the reader to go look. Article 20 changes that by giving the loop a sensor. The agent (or the orchestrator running the agent) can subscribe to the same telemetry the reader uses, and the verification step becomes mechanical.

The teaching: **a prompt contract is intent → action → verification**, and Article 20 is where verification stops being aspirational. When an agent applies a change, the next step in the workflow is reading the relevant metric: BGP session came up within N seconds, interface counters started incrementing, no error logs appeared. This is the closing brace on every agentic loop the rest of the series uses.

Two patterns the article should teach:

- **Telemetry-anchored verification.** A bad prompt is "apply this change." A good prompt is "apply this change; the expected effect is that BGP neighbor X transitions to Established within 30 seconds and interface Y's `out-octets` begins incrementing; query Prometheus for both, report success or failure with the actual values." The agent's report is now grounded in observed reality, not its belief about what should have happened. The reader can audit the report by reading the same Prometheus.
- **Anomaly triage from telemetry plus context.** A spike in interface errors, a flap, a sudden latency increase — these are the moments humans currently grep through. The agent given the metric plus recent change history from Git (the link back to [[article-06-git]]) can produce a short-list of hypotheses faster than the reader can grep. The reader runs the verifications, but the hypothesis space is pre-filtered.

The honest caveat to surface: **statistical anomaly detection is genuine ML, and is a different thing than an LLM reading metrics in context.** Some of the value here is from anomaly-detection systems (which the reader should know about and consider for high-volume telemetry); some is from an LLM correlating low-volume signals with recent changes. The article should distinguish the two to keep the reader honest when they're evaluating vendors in [[article-24-aiops-ibn]].

The forward-looking note: **[[article-22-ci-cd]]'s pipeline uses telemetry as its post-deploy verification step; [[article-23-mcp]]'s MCP server exposes telemetry queries as a tool; [[article-24-aiops-ibn]] is essentially a discussion of where telemetry-driven automation can responsibly go.** Article 20 is the substrate every later article assumes.

## Concepts and entities introduced

- [[streaming-telemetry]] (deepened from stub)
- [[prometheus]] (deepened from stub)
- [[grafana]] (deepened from stub)

## Open questions

_(none yet)_
