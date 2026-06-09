
# Article 20b — Advanced CNI: Cilium and eBPF (optional extension)

An optional advanced companion to [[article-20-kubernetes-networking]]. The main article uses [[cni]] = Calico for its network-engineer-friendly dissection; this one returns to the same lab with **Cilium** and treats **eBPF** as the subject rather than an obstacle.

The reader who finishes Article 19 is equipped to evaluate Cilium critically. The reader who finishes 16b can also *operate* it — and can speak credibly about where the industry is heading, since Cilium is the trajectory winner across managed K8s offerings.

## Expected outcome

The reader finishes the article able to:

- Articulate what eBPF actually is (in-kernel programmable hooks), where it lives, and why it matters operationally — not just as a buzzword.
- Deploy Cilium on a local [[k3s]] cluster and observe its dataplane behavior.
- Use **Hubble** for service-map and flow visibility, and compare what it shows to what `tcpdump` would have shown under Calico.
- Reason about Cilium's **identity-based** network policies (versus IP/label-based) and connect them to the [[zero-trust-network-access]] model from [[article-19-ztna]].
- Make a defensible Calico-vs-Cilium recommendation for a real shop based on workload, team skills, and observability needs.

## Outline

1. **Why this article exists.** Article 19 deliberately picks Calico for legibility. Cilium is genuinely different — different enough to deserve its own dissection, on its own terms. Reader should leave able to argue both sides credibly.
2. **eBPF, from first principles.** In-kernel sandbox for safe programs attached to hooks (XDP, TC, kprobes, tracepoints). What it replaces (iptables, kernel patches, sidecar proxies). What it can't do.
3. **Cilium's dataplane.** How packets actually move: XDP at NIC ingress, TC for pod-to-pod, kube-proxy replacement, socket-level load balancing. The contrast with iptables-based CNIs.
4. **The observability story: Hubble.** Service maps, flow logs, L7-aware visibility (HTTP, gRPC, Kafka, DNS) without sidecars. What this gives you operationally that `tcpdump` does not.
5. **Identity-based policy.** Cilium's identity model — workloads identified by labels, not IPs; policy expressed on identities, not network locations. The connection to [[zero-trust-network-access]]: this is the K8s-native expression of the same principle [[openziti]] applies to the broader network.
6. **The honest trade-offs.** Where Cilium is the right answer (cloud-native shops, deep L7 visibility needs, eBPF-fluent platform teams). Where Calico is still the right answer (BGP integration with existing fabric, network-engineer-owned clusters, simpler operational surface). Where the cloud's bundled CNI wins regardless of the comparison.
7. **Lab walkthrough.** Same k3s topology as Article 19, but with Cilium installed and the iptables/IPVS stack disabled. Run the same `kubectl exec` curl from Article 19. Run Hubble alongside. Apply an identity-based policy. Compare what observability gives you.
8. **The bigger picture briefly.** Cilium Mesh / Cluster Mesh, Cilium Service Mesh, the eBPF-driven future of L7 observability and policy. Where this overlaps with service-mesh territory; where it doesn't.
9. **How LLM agents fit here.** Callback to tool design, sized for eBPF's specific operational shape.

## Lab

Reader brings up:

1. A fresh [[k3s]] cluster (or destroys and redeploys the Article 19 cluster) with the default CNI disabled and Cilium installed via Helm.
2. The same two-pod workload from Article 19, plus a third pod with deliberately mismatched labels for policy testing.
3. **Hubble UI** running locally, showing real-time flows.
4. An identity-based **CiliumNetworkPolicy** allowing pod A to talk to pod B over HTTP only (L7-aware).
5. Exercises:
   - `cilium status` and `cilium connectivity test` for sanity.
   - Issue curls from pod A and pod C; observe Hubble showing which were allowed, which dropped, and *at what layer* (L3? L4? L7?).
   - Inspect attached eBPF programs with `bpftool` to see where they live in the kernel.
   - (Stretch) Configure **Cilium BGP control plane** so the cluster peers with a containerlab cEOS spine; observe pod-IP advertisement into the fabric — the same outcome as Calico-BGP, but via Cilium.

The keepable artifact: a Cilium-backed k3s deployment with Hubble dashboards, plus a one-page written comparison the reader produces of "what I saw under Calico vs what I see under Cilium."

## Foundational material needed

| Prerequisite | Covered where | Notes |
|---|---|---|
| All of Article 19's prerequisites | **[[article-20-kubernetes-networking]]** | This is an extension; everything Article 19 required applies here |
| Article 19 itself | **[[article-20-kubernetes-networking]]** | The Calico baseline is the comparison surface |
| ZTNA identity-and-policy model | **[[article-19-ztna]]** | Cilium's identity-based policy is the K8s-native flavor of the same idea |
| Basic Linux kernel awareness | **External** — light treatment in the article | Reader gets enough eBPF mental model to be productive without becoming a kernel developer |
| Helm | **External** — pointer in the lab setup | Cilium is installed via Helm; reader gets the commands |

The article is explicitly **optional**. Skipping it leaves no downstream gap — Articles 20–23 do not depend on it. Reading it deepens the reader's K8s-networking position and prepares them for shops where Cilium is the default.

## Assumed networking knowledge

External prerequisites the reader brings in. See [[assumed-networking-knowledge]] for the series-wide picture.

- Linux kernel awareness at concept level: hooks, programs running in-kernel
- XDP, TC, kprobes, tracepoints as named kernel attachment points (light treatment here)
- iptables operational pain (rule explosion, ordering, debugging) — what eBPF replaces
- kube-proxy purpose and what it does on the wire
- Service-mesh territory: sidecars, L7 visibility, mTLS between workloads
- Cilium BGP control plane peering with a ToR cEOS
- L7 protocol awareness: HTTP, gRPC, Kafka, DNS — enough to know what L7 visibility means
- Everything from [[article-20-kubernetes-networking]]

## How LLM agents fit here

A **callback** article in the agentic curriculum. No new agentic concept is introduced; the article does two useful things on the existing patterns:

- **The eBPF tooling surface is dense and idiomatic, and an LLM agent earns its keep navigating it.** `bpftool prog show`, `cilium-dbg`, `hubble observe`, raw `bpftrace` scripts — these are exactly the kind of structured-output-but-hard-to-skim surfaces where an agent reading the output and proposing the next command saves real time. The verification habit from [[article-01-linux-for-network-engineers]] carries over unchanged: the reader runs the command, the agent interprets, the reader checks the interpretation against the K8s state.
- **Identity-based policy connects to [[article-19-ztna]]'s "agents as identities under policy" treatment.** Cilium's CiliumNetworkPolicy is the K8s-native answer to "what is this workload (or this agent) allowed to reach." If the reader is exposing an MCP server ([[article-23-mcp]]) inside a Cilium-backed cluster, the policy that bounds the agent's reach can live in Cilium itself rather than in [[openziti]] — same principle, different layer.

The article should also be honest about a Cilium-specific friction: **eBPF's main downside is that when something goes wrong, the debug surface is at the kernel level**, and an LLM that confidently explains a `bpf_trace_printk` output can also confidently explain a hallucinated one. The verification discipline matters more here than in `iptables`-land, where Linux gives you decades of forum posts the model has actually trained on. Trust but verify; verify in particular when the model is being confident about eBPF internals.

## Concepts and entities introduced

- **Cilium** — would get its own entity page if/when this article ships
- **eBPF** — would get its own concept page if/when this article ships
- **Hubble** — would get its own entity page

(Not yet creating those pages; they can land alongside the article when it's drafted.)

## Open questions

- **When to schedule.** This article doesn't block any other article and is genuinely optional. Could ship as the first follow-on to the core 20 series, or much later. No urgency, but worth picking a slot when the author returns to the curriculum.
- **Whether to add a parallel "Calico advanced" companion** — covering Calico's eBPF dataplane (yes, Calico has one too), policy-as-code with Calico Cloud, BGP route reflectors, etc. Probably not needed; Article 19 with the SD-Access lab in Article 17 covers the territory.
