
# Article 16 — Cloud Networking Hands-On with LocalStack

With cloud concepts from first principles in hand (Article 14), the reader now interacts with cloud networking the way they will at work — through APIs and infrastructure as code — but with zero cloud spend.

## Expected outcome

The reader finishes the article able to:

- Provision cloud networking with [[terraform]]: VPCs, subnets, route tables, internet gateways, security groups, peering.
- Run all of it against [[localstack]] locally, then translate the same code to target real AWS.
- Understand the gap between LocalStack and real cloud — what transfers cleanly, what doesn't.
- Transfer their muscle memory to Azure or GCP equivalents with the same translation discipline from Article 14.

## Outline

1. **Why this article exists.** The Article 14 primitives now meet a real cloud API surface. Reader does the labs without paying AWS.
2. **LocalStack briefly.** Community Edition: what it emulates, what it doesn't, where to read the truth.
3. **AWS networking constructs revisited, now as APIs.** VPC, subnet, route table, IGW, NAT gateway, security group, VPC peering — what each looks like in Terraform AWS provider, called against LocalStack.
4. **The hands-on flow.** `terraform init && terraform plan && terraform apply` against `localstack` endpoint configuration. See the resources show up via the LocalStack dashboard or `awslocal` CLI.
5. **Translating to real AWS.** The same Terraform code, retargeted at real AWS with read-only credentials. Show that the muscle memory transfers. Be explicit about the few things that don't (some service quotas, region selection, IAM nuances).
6. **Azure and GCP, briefly.** The translation pattern again: same primitives, different API surface. Don't teach it deeply; point at the docs.
7. **Lab walkthrough.** Build a two-VPC topology with peering against LocalStack using Terraform.
8. **How LLM agents fit here.** Callback to [[article-12-containerlab]]'s sandbox pattern, applied to cloud APIs.

## Lab

Reader writes Terraform that:

1. Configures the AWS provider to target the local LocalStack endpoint.
2. Declares two VPCs in different CIDR ranges.
3. Subnets and route tables in each.
4. A VPC peering connection between them.
5. Security groups allowing the right traffic.
6. `terraform plan`, `apply`, verify with `awslocal ec2 describe-vpcs` and friends.
7. (Stretch) Retarget the same code at real AWS with read-only credentials; observe the plan succeeds (or fails informatively) without spending money.

## Foundational material needed

| Prerequisite | Covered where | Notes |
|---|---|---|
| Cloud networking primitives | **[[article-15-cloud-concepts]]** | Direct upstream |
| Terraform | **[[article-13-terraform]]** | The lab is Terraform end-to-end |
| Docker | **[[article-11-docker]]** | LocalStack runs in Docker |
| Git | **[[article-06-git]]** | Code lives in a repo |
| YAML/HCL fluency | **[[article-07-structured-data]]** | Article 12's HCL grounding |

A "callback" article — no new agentic concept introduced, but the prerequisite list is the longest in the series so far, because this is where the cloud cluster pays off everything that came before.

## Assumed networking knowledge

External prerequisites the reader brings in. See [[assumed-networking-knowledge]] for the series-wide picture.

- AWS networking constructs at the *name* level: VPC, subnet, route table, IGW, NAT gateway, security group, VPC peering (carried in from [[article-15-cloud-concepts]])
- Cross-cloud awareness: Azure and GCP have the same primitives renamed
- IAM and region selection as operational concerns adjacent to networking
- API rate limits and backoff as networking-adjacent operational realities

## How LLM agents fit here

A **callback** article. No new agentic concept is introduced; the article reuses the sandbox-first pattern from [[article-12-containerlab]], applied to a new sandbox: LocalStack. The same logic that made containerlab safe to let an agent operate in applies here — LocalStack is ephemeral, isolated, and costs nothing to destroy, which means the agent can iterate freely on Terraform code against it without the rate limits, blast radius, or billing exposure of real AWS.

Two patterns worth surfacing briefly:

- **LocalStack as the agent's cloud sandbox.** The reader's `plan`/`apply` workflow from [[article-13-terraform]] composes cleanly: agent generates Terraform, plan runs against LocalStack, reader reviews the plan, apply runs against LocalStack. Once the cycle stabilizes there, the same module gets pointed at real AWS — at which point the reader, not the agent, is the one retargeting. The agent operates inside the sandbox; promotion to production is a human decision, just as with containerlab.
- **Cross-cloud translation.** Same pattern as Article 14 but with the agent now also helpful for AWS↔Azure↔GCP translation of Terraform modules. "Translate this AWS VPC module to a GCP VPC equivalent." Useful because the underlying concepts are stable but the resource names differ by hundreds of small details. Verification: run `terraform plan` against the target cloud (or its emulator) and read the diff.

A specific wrinkle to note in the article that doesn't apply to [[article-12-containerlab]]: **even in a sandbox, cloud API rate limits matter.** An agent that iterates by retrying every five seconds will get throttled or banned even by LocalStack. Tooling the agent with a retry/backoff helper is part of safe agentic operation against any cloud API, sandbox or not.

The forward-looking note is short here: cloud APIs are tool surfaces in the same sense [[article-10-rest-apis]] introduced. Wrapping them as MCP tools is straightforward; [[article-23-mcp]] will show this if the reader wants to extend the capstone toward cloud.

## Concepts and entities introduced

- [[localstack]] (deepened from stub)

## Open questions

_(none yet)_
