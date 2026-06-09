
# Article 15 — Cloud Networking Concepts from First Principles

The article that defuses cloud-networking intimidation by showing the primitives are the same. Before touching cloud APIs, the reader should understand what cloud networking primitives actually *are* — a VPC is a routing domain, a subnet is a CIDR with a route table association, a transit gateway is a route reflector.

## Expected outcome

The reader finishes the article able to:

- Map any cloud networking concept to its underlying primitive (routing domain, CIDR, NAT, route reflector, attachment).
- Articulate what's the same and what's genuinely different about cloud networking.
- Approach AWS/Azure/GCP networking documentation without intimidation, because they've already built the primitive in Linux.

## Outline

1. **Why this article exists.** Cloud networking is presented (and often perceived) as a separate discipline. It is not. The primitives are familiar; the packaging is new.
2. **The translation table.** VPC ↔ routing domain. Subnet ↔ CIDR with a route table association. Route table ↔ a routing table the reader's already seen in `ip route`. Internet gateway ↔ default route plus NAT. Transit gateway ↔ route reflector + interconnect. Security group ↔ stateful firewall. NACL ↔ stateless filter.
3. **Building each primitive in Linux.** Using namespaces and FRR (from Article 1's substrate), build:
   - A "VPC" — a namespace with its own routing table.
   - A "subnet" — a CIDR associated with a routing context.
   - "Subnet-to-subnet routing" — multiple subnets in one VPC.
   - "Transit gateway" — a third namespace running BGP to peer two "VPCs".
   - "Internet gateway" — a NAT'd egress.
4. **What's actually different in real cloud.** API surface (the next article). Scale (managed control plane). Constraints (cloud-specific quotas, blast-radius patterns, billing surprises). Be honest about what doesn't fully translate.
5. **Lab walkthrough.** Build the entire above topology with `ip netns` and FRR in containerlab. The reader sees their own "VPC" routing across their own "transit gateway."
6. **How LLM agents fit here.** Callback to Article 1's translator pattern.

## Lab

Reader brings up a [[containerlab]] topology that runs:

1. Two "VPCs" as namespaces with FRR.
2. Three "subnets" each (more namespaces, more veth pairs).
3. A "transit gateway" namespace running BGP to both VPCs.
4. An "internet gateway" namespace with masquerade NAT to the host's external interface.

Reader traces a packet from "subnet 1 in VPC A" to "subnet 2 in VPC B" with `tcpdump`, then from "subnet 1 in VPC A" out the "internet gateway."

The artifact is a topology and a packet trace that proves the reader built a cloud-shaped network from Linux primitives.

## Foundational material needed

| Prerequisite | Covered where | Notes |
|---|---|---|
| Linux fluency, especially [[network-namespaces]] | **[[article-01-linux-for-network-engineers]]** | This article is Article 1's downstream payoff |
| FRR basics | **External**, light treatment in the article | Reader has met `frr` as a name; this is where it gets used |
| Containerlab | **[[article-12-containerlab]]** | Lab substrate |
| BGP fundamentals | **External** — assumed | Reader's existing network background carries this |

This is a "callback" article in the agentic curriculum — most prerequisites are upstream and external. The contribution is conceptual, not new agentic content.

## Assumed networking knowledge

External prerequisites the reader brings in. This is the article where **BGP is explicitly external** — without it, the cloud-primitives mapping does not land. See [[assumed-networking-knowledge]].

- BGP fundamentals (sessions, neighbors, advertisement, best-path) — explicitly external
- Route reflectors as a routing-plane pattern (the cloud transit-gateway analogy)
- NAT and masquerade
- Stateful vs stateless firewalls (the security-group vs NACL split)
- CIDR notation and subnetting fluency
- Default routes and Internet egress patterns
- VRF / routing-table-per-tenant — the foundational analogy "a VPC is a VRF"
- Policy routing (`ip rule`)
- FRR / software BGP speaker awareness
- Overlay networks as a general category

## How LLM agents fit here

Article 14 is the first **callback** article in the agentic arc. No new agentic concept is introduced here; the article reuses the *translator* framing from [[article-01-linux-for-network-engineers]] applied to a new asymmetry — the reader knows on-prem networking, the cloud has rebranded the same primitives, and an LLM is well-suited to translate.

The pattern: the reader names the cloud construct ("what does AWS mean by a 'route table association'?"), the agent maps it to the primitive the reader already understands ("a binding from a subnet to a specific routing table; you've already built this with `ip rule add iif`"), and the reader verifies against the Linux equivalent they're standing on. Just as in Article 1, the agent has no tools and no access — it's read-only by construction, and the reader's existing competence is the verification surface.

Two short additions worth dropping into the article:

- **The agent is also good at the reverse translation.** "I built this in Linux namespaces; what's the AWS equivalent I'd reach for?" Useful when the reader needs to move a lab understanding into a real-cloud conversation.
- **Be honest about hallucination risk.** Cloud provider documentation changes; the agent may know an outdated version. Verification against the provider's current docs is non-optional. The verification habit from Article 1 carries forward unchanged.

The next article ([[article-16-localstack]]) is where the agent gets back into the act, with the LocalStack API as the new tool surface.

## Concepts and entities introduced

- (No new concept pages — Article 14 builds on existing ones: [[network-namespaces]], [[frr]], [[overlay-network]])

## Open questions

_(none yet)_
