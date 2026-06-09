
# Article 10 — REST APIs for Network Devices (flagship)

The first deep-dive article and a flagship of the series. Covers Arista [[arista-eapi]] in detail with overviews of [[restconf]], [[netconf]], and [[gnmi]] so the reader sees the broader landscape.

## Expected outcome

The reader finishes the article able to:

- Interact with any modern network device API confidently — read the spec, hit the endpoint, parse the response.
- Articulate the protocol options ([[arista-eapi]], [[restconf]], [[netconf]], [[gnmi]]) and the trade-offs that pick between them.
- Build a small, useful tool against a real device (the lab produces a config drift detector worth keeping).
- Recognize the device API as the **agent's tool surface** — and design tool boundaries accordingly.

## Outline

1. **Why this article exists.** CLI scraping is a tax. Structured APIs are the modern interface. A network engineer who can't speak them is locked out of automation conversations.
2. **The protocol landscape, briefly.** [[arista-eapi]] (JSON-RPC), [[restconf]] (HTTP/REST against YANG), [[netconf]] (XML/SSH against YANG), [[gnmi]] (gRPC against YANG, plus streaming). What each is, when it's the right answer.
3. **eAPI deep dive.** JSON-RPC request shape. The `runCmds` envelope. Authentication. `text` vs `json` output. Multi-command transactions. Error handling.
4. **Hands-on with `curl`.** Hit eAPI directly. See the raw request and response. Strip away the libraries for a moment.
5. **Hands-on with Python.** The `pyeapi` library *or* raw `requests`. Build the same call programmatically. Compare.
6. **Cross-reference: RESTCONF, NETCONF, gNMI.** One worked example per protocol against a device that supports them. Just enough to recognize the shapes.
7. **Building a useful tool.** A config drift detector: pull the running config from a device, compare against a known-good baseline in Git, report differences. ~100 lines of Python; the reader extends it as homework.
8. **How LLM agents fit here.** APIs as tool surfaces — the first article where the agent acquires *tools* in the agentic sense.

## Lab

Reader uses the cEOS topology from the lab harness (full treatment in Article 11):

1. Authenticates to eAPI on a single cEOS node with `curl`.
2. Issues `show version` and `show running-config`. Reads the JSON-RPC response by eye.
3. Rewrites the same call in Python with `requests`.
4. Adds three more devices, loops over them.
5. Compares each running config against a baseline file checked into Git, reports drift.
6. (Stretch) Repeats the read with RESTCONF or gNMI against a supporting device for protocol contrast.

The drift detector is the keepable artifact.

## Foundational material needed

| Prerequisite | Covered where | Notes |
|---|---|---|
| Linux fluency, `curl` | **[[article-01-linux-for-network-engineers]]** | |
| Git for the baseline configs and tool source | **[[article-06-git]]** | |
| JSON fluency for request/response | **[[article-07-structured-data]]** | Critical — eAPI is JSON-RPC end to end |
| Python (`requests`, file I/O) | **[[article-08-python]]** | The drift detector is Python |
| Ansible mental model | **[[article-09-ansible]]** | Useful for contrast: this article is *imperative* API calls, Article 8 was declarative state |
| A cEOS topology | **[[article-12-containerlab]]** — *not yet covered* | Article 9 uses a pre-packaged lab harness; Article 11 unpacks it. Article 9's flagship status means it appears before Containerlab gets its own deep dive |
| YANG basics | **External** — light pointer in the RESTCONF/NETCONF/gNMI section | Not taught; reader is given enough to recognize the term |

This is the first article that materially depends on multiple earlier articles. It also forward-references Article 11 — by design, the reader uses the lab platform here and learns its internals later.

## Assumed networking knowledge

External prerequisites the reader brings in. See [[assumed-networking-knowledge]] for the series-wide picture.

- JSON-RPC envelope mental model (or willingness to acquire it from one example)
- `show version`, `show running-config` as canonical read commands
- `enable; configure terminal` privilege model
- VRF, interface, device hostname as the scope axes a tool dispatches on
- YANG as a name (explicitly external — not depended on here)
- Authentication against a network device (username/password, token, certificate)
- Config drift as an operational concept (drift vs baseline)
- Multi-command transactions on a device and why atomicity matters

## How LLM agents fit here

This is the article where the reader first sees a network device API the way an LLM agent sees it: as a **tool**. Up through Article 8 the agent was producing artifacts (translations, commit messages, scripts, playbooks) that a human ran. From Article 9 on, an agent *could* be the thing calling the API — and the article needs to introduce tool design carefully before later articles assume it.

The core teaching: **a tool is an API surface deliberately shaped for an agent to use safely and predictably.** Three properties matter:

1. **Structured I/O.** JSON-RPC over HTTP is dramatically friendlier to an LLM than CLI scraping. Structured input is easier to generate correctly; structured output is easier to parse and verify. This is the principle from Article 6 cashed in. The reader should leave Article 9 understanding *why* the industry's trajectory is toward [[gnmi]] and [[restconf]] and away from screen-scraping — it's the same reason agents prefer them.
2. **Read-write separation.** `show version` and `enable; configure terminal; ...` should not be the same tool, even if the underlying API technically allows it. When an agent has tools, "read state" and "change state" should be different tools with different permissions and different approval requirements. The reader sees the raw eAPI in Article 9 — both halves available behind one endpoint — and learns that *the agent's tool wrapper, not the API itself, is where the safety lives*. This idea reappears as a full pattern in [[article-23-mcp]].
3. **Scope as a tool parameter.** A `get_running_config` tool that takes a device hostname is safer than a `get_running_config` tool that operates on whatever device the agent decides. Scope — which device, which VRF, which interface — should be an explicit argument the agent must provide and the orchestrator can constrain.

The reader's practical exercise here is the inverse of an agent's: they write the Python that calls the API, but they should write it *as if they were defining a tool*. The drift-detector script naturally splits into a `get_running_config(device)` function and a `compare_against_baseline(device, baseline)` function. Each is a candidate MCP tool with little additional work — and when the reader reaches [[article-23-mcp]], they'll see those exact shapes again.

The forward-looking note worth dropping in this article: **everything that comes later — streaming telemetry as a sensor in [[article-21-observability]], CI/CD gates in [[article-22-ci-cd]], the MCP server in [[article-23-mcp]] — is built on the device-API-as-tool foundation laid here.** Article 9 is the flagship not because eAPI is the most important protocol, but because it's where the *agent's hands start to learn what they can hold*.

A productive prompt pattern to introduce: hand the agent the OpenAPI spec (or, for eAPI, the command reference) and ask it to generate the client function for a specific call, including type hints and error handling. The reader gets a working stub faster than reading docs end-to-end; the verification is running it against the cEOS container and reading the response.

## Concepts and entities introduced

- [[arista-eapi]]
- [[restconf]]
- [[netconf]]
- [[gnmi]]

## Open questions

_(none yet)_
