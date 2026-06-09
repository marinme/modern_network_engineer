
# Article 07 — YAML, JSON, and Structured Data

The article that converts the reader from "I can read it if I squint" to fluent. Modern network automation runs on structured data; the ability to read, write, and validate it is non-negotiable.

## Expected outcome

The reader finishes the article able to:

- Read and write YAML and JSON without the common foot-guns (whitespace, type coercion, anchors and aliases, escaping).
- Recognize good vs bad schema design — when nesting helps, when it just hides information.
- Use `jq` and `yq` to transform structured data on the command line.
- Validate data against a schema and understand what a schema is *for* operationally.
- Use an LLM to generate and to validate structured data, with the structure itself as the verification contract.

## Outline

1. **Why this article exists.** Every modern tool — [[ansible]], [[terraform]], [[netbox]], [[containerlab]], CI pipelines, device APIs — speaks structured data. The reader cannot be effective without fluency.
2. **YAML by example, including the foot-guns.** Whitespace significance, the Norway problem (`no` becoming `false`), implicit types, multi-line strings, anchors and aliases. Show each pitfall with the broken-then-fixed pair.
3. **JSON by example.** Smaller surface than YAML, fewer foot-guns, almost always what an API actually sends. When to use which.
4. **`jq` and `yq` as the surgical tools.** Filtering, projecting, transforming, converting between formats. A handful of one-liners worth memorizing.
5. **Schema as a contract.** JSON Schema basics. Why a schema is operationally useful: it's a precommit check, a documentation artifact, and (later in the series) an LLM contract.
6. **Lab walkthrough.** Take a device inventory in one format, transform it, validate it against a schema, deliberately break it to see the validator complain.
7. **How LLM agents fit here.** Structured I/O as the LLM's verification surface. First real prompt-engineering content in the series.

## Lab

Reader is given:

1. A device inventory in YAML.
2. A target JSON shape (perhaps what an [[ansible]] inventory plugin or [[netbox]] bulk-import expects).
3. A JSON Schema describing the target.

Reader uses `yq`/`jq` to transform YAML → JSON, then validates against the schema. The exercise repeats with deliberately malformed input so the reader sees what a validator failure looks like and how to read it.

## Foundational material needed

| Prerequisite | Covered where | Notes |
|---|---|---|
| Shell fluency | **External** — and reinforced by Articles 1–2 | |
| Linux command-line tooling | **[[article-01-linux-for-network-engineers]]** | `cat`, pipes, redirection |
| Comfort editing files in a repo | **[[article-06-git]]** | The lab can optionally be done in a sample repo to compound practice |
| Python/Jinja templating | **[[article-08-python]]** + **[[article-09-ansible]]** | *Not yet covered* — Article 6 stays at the data layer; templating is deferred |

This article completes the Foundation cluster. After Article 6, the reader has a Linux box, a version-controlled repo, and the structured-data fluency every subsequent article assumes.

## Assumed networking knowledge

External prerequisites the reader brings in. See [[assumed-networking-knowledge]] for the series-wide picture.

- Device inventory as a concept: hosts, groups, attributes
- Interface naming conventions (for cross-file consistency checks)
- General familiarity with vendor config files

## How LLM agents fit here

This is the first article that does real **prompt-engineering work**, because structured data is what gives LLM output a verification surface. Up through Article 6 the agent's outputs were prose the reader judged with their own eyes. From Article 7 on, the agent's outputs can be *checked* — by `jq`, by a JSON Schema validator, by a deterministic round-trip. That changes what's safe to delegate.

The two core moves taught here:

**Generation against a schema.** A bad prompt is "give me an Ansible inventory." A good prompt provides the JSON Schema (or a worked example) and says "produce data matching this exact shape for the following devices." The schema becomes the contract; the validator becomes the test. When the agent's output passes the validator, the reader has cheap mechanical evidence that the structure is right — they only need to check the semantics. This is the verification habit from Article 1, but now the verification is partly automated.

**Validation as an LLM task.** Hand the agent a chunk of someone else's YAML and ask "what's structurally suspect here, and what's semantically suspect given that this is a device inventory." The agent flags the easy things (a string where a number was expected, an indentation that's almost certainly wrong, a duplicate key) and proposes hypotheses for the harder things (an interface name that doesn't match any other in the file). Reader still owns the judgment call, but the agent is now doing real review work.

This article is where the reader should also be told, plainly: **the more structured the agent's input and output, the more trustworthy the loop**. Prose in, prose out is fragile. Schema in, schema-conformant out, deterministically validated, is the shape every later agentic workflow in the series aspires to. [[article-13-terraform]]'s `plan` output, [[article-14-netbox]]'s SoT, [[article-22-ci-cd]]'s test gates, and [[article-23-mcp]]'s tool I/O are all instances of the same principle introduced here.

## Concepts and entities introduced

- [[yaml]]
- [[json]]

## Open questions

_(none yet)_
