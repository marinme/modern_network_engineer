
# Article 20 — Kubernetes Networking for Network Engineers

The article that demystifies the network layer where modern applications run. Kubernetes is where many network engineers get tripped up because the abstractions don't map cleanly to traditional concepts — Article 19 makes the mapping explicit.

## Expected outcome

The reader finishes the article able to:

- Troubleshoot [[kubernetes]] networking with the same `tcpdump` and `ip route` tools they use everywhere else.
- Articulate the design choices behind common [[cni]] plugins (Calico, Cilium, Flannel) and pick between them.
- Hold credible conversations with platform teams about cluster networking.
- See the agent operating across two control planes (Kubernetes + network) as a multi-tool extension of [[article-10-rest-apis]].

## Outline

1. **Why this article exists.** Kubernetes networking is presented as developer territory; it isn't. Pods send packets; packets traverse interfaces; interfaces are network engineering. The reader is the right person to debug this.
2. **The shapes the reader needs.** Pods, services, ingress, network policies — defined network-engineer-first ("a Service is a stable virtual IP fronting a set of pod IPs via iptables/IPVS").
3. **What CNI actually is.** A plugin interface. What it does (assigns the pod IP, configures the interface, plumbs reachability). What's hidden behind it.
4. **The CNI landscape, briefly.** Flannel (overlay, simple). Calico (BGP, no overlay if you want — **the series default**, picked for legibility under traditional tools). Cilium (eBPF, advanced features — covered separately in the optional advanced [[article-20b-cilium-ebpf]]). What picks between them, and what the reader will actually encounter at work: self-managed enterprise → mostly Calico; AWS EKS → AWS VPC CNI; Google GKE → Cilium via Dataplane V2; Azure AKS → Azure CNI. The lab teaches Calico because it's the most network-engineer-legible; the patterns transfer.
5. **Pod-to-pod traffic, decomposed.** A packet from one pod to another, traced end-to-end with `tcpdump` and `ip route` on the host. The abstraction is now an interface the reader can see.
6. **Services, ingress, and the L4/L7 boundary.** Where iptables ends and a reverse proxy begins.
7. **Network policies.** Kubernetes' native segmentation. A second pass over the policy-based access idea from [[article-19-ztna]] — same model, different layer.
8. **Lab walkthrough.** [[k3s]] locally with Calico (BGP mode) replacing the default Flannel; deploy two pods; trace traffic between them with traditional tools; apply a NetworkPolicy; verify enforcement; (stretch) peer the Calico BGP control plane with a [[containerlab]] cEOS spine to demonstrate the cluster joining a real fabric.
9. **How LLM agents fit here.** Callback to tool design — agents working across the K8s API and the host network stack as a two-tool problem.

## Lab

Reader:

1. Brings up k3s on the local Linux box with **Flannel disabled and Calico installed** (BGP mode, no overlay). Single-node is fine.
2. Deploys two pods (e.g., two `nginx` instances with different labels).
3. From the host, identifies the pod IPs (real routable IPs under Calico-BGP), inspects the host route table with `ip route` and sees pod prefixes installed natively.
4. Runs `tcpdump` on the appropriate host interface during a `kubectl exec` curl; sees the actual packets — no encapsulation hiding them.
5. Applies a NetworkPolicy denying cross-label traffic; re-tests; verifies enforcement.
6. (Stretch) Peers Calico's BGP control plane with a [[containerlab]] cEOS spine; observes pod-IP advertisement into the fabric — the cluster is now a fabric participant, not an island behind NAT.
7. (Pointer) For the eBPF-and-Hubble version of the same lab, see [[article-20b-cilium-ebpf]].

## Foundational material needed

| Prerequisite | Covered where | Notes |
|---|---|---|
| Linux fluency, `tcpdump`, `ip route` | **[[article-01-linux-for-network-engineers]]** | Foundational; this article relies on it heavily |
| Docker | **[[article-11-docker]]** | k3s is containerized; pods are containers |
| YAML | **[[article-07-structured-data]]** | Manifests are YAML |
| Containerlab (optional) | **[[article-12-containerlab]]** | Not strictly required; k3s runs directly |
| Network policy framing | **[[article-19-ztna]]** | The policy model from Article 18 generalizes here |
| CNI choice for the lab | **Resolved** — [[q-which-cni-for-network-engineer-lab]] → Calico (BGP mode) | Cilium and eBPF treated separately in [[article-20b-cilium-ebpf]] |

## Assumed networking knowledge

External prerequisites the reader brings in. See [[assumed-networking-knowledge]] for the series-wide picture.

- iptables / IPVS rule-chain mental model (or `nftables` from [[article-01-linux-for-network-engineers]])
- BGP — specifically host-level / unnumbered BGP for Calico
- Overlay vs underlay routing as a design choice (Flannel vs Calico-BGP)
- L4 vs L7 distinction; reverse proxies and ingress
- Network policy / segmentation as a packet-filter problem
- DNS as a service-discovery mechanism
- Pod IP routability — NAT vs no-NAT and why it matters
- Service / virtual-IP load balancing
- Awareness that cloud-managed K8s has variant networking (AWS VPC CNI, Azure CNI, GCP Cilium / Dataplane V2)
- BGP peering between a cluster and a top-of-rack switch (cluster-as-fabric-participant)

## How LLM agents fit here

A **callback** article focused on the *tool-design* idea from [[article-10-rest-apis]]. Kubernetes networking surfaces a useful complication: the agent now has to reason across two control planes at once — Kubernetes (declarative manifests, API server, controllers) and the host network stack (interfaces, routes, iptables, eBPF). Each is its own tool surface; effective agentic operation needs both.

The teaching: **multi-tool agentic operation is the same single-tool pattern, repeated and composed.** The agent gets a `kubectl_get` tool, a `kubectl_apply` tool (gated, like Terraform `apply`), a `host_ip_route` tool, a `host_tcpdump` tool (read-only). The agent uses them in sequence to investigate ("get the pod, find its IP, check the route on the host, capture the traffic"). Each tool is structured I/O, read-write-separated, scoped — the same three properties [[article-10-rest-apis]] introduced. The novelty is *composition*, not the tools themselves.

Two patterns the article should surface briefly:

- **Cross-plane diagnosis.** The classic Kubernetes networking failure is "pod can't reach service" — and the answer might live in a manifest (wrong selector), in iptables (kube-proxy rules), in the CNI (route missing), or in the host (firewall). An agent given access to all four can localize the problem in seconds; the reader's role is to verify the agent's hypothesis with a deterministic check (`kubectl get`, `iptables-save | grep`, `ip route get`). This is the [[article-17-vxlan-evpn]] troubleshooting pattern repeated against a different fabric.
- **CNI choice as an LLM-aided design conversation.** The agent is a credible sounding board for "given these workloads, this scale, this team's expertise — which CNI?" — bounded by the engineer's verification. The agent will produce a reasonable shortlist with trade-offs; the engineer picks. This is the agent-as-design-assistant role from [[article-17-vxlan-evpn]], applied to a cluster networking decision.

No new agentic concept is introduced; the value is in seeing the [[article-10-rest-apis]] tool-design pattern compose across two control planes, which is exactly what [[article-23-mcp]] will then formalize for a network as a whole.

## Concepts and entities introduced

- [[kubernetes]] (deepened from stub)
- [[k3s]] (deepened from stub)
- [[cni]] (deepened from stub)

## Open questions

_(none — [[q-which-cni-for-network-engineer-lab]] resolved 2026-06-01: Calico for the main lab; Cilium covered in optional [[article-20b-cilium-ebpf]])_
