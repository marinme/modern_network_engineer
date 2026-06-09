
# Article 08 — Python Primer for Network Work

The Automation Primer cluster's entry point. The reader has structured data fluency from [[article-07-structured-data]]; this article hands them Python as the scripting language they will reach for whenever YAML and `jq` are not enough — which is more often than they think.

The framing is **just enough Python to be dangerous**, not Python-as-a-language. The reader is not training to be a software engineer; they are training to write a 30-line script that reads a NetBox export, applies a transformation, and emits a config snippet. Every example in the article serves that use case.

## Expected outcome

The reader finishes the article able to:

- Write a script that reads YAML or JSON, applies a transformation, and writes the result back — the bread-and-butter network-automation shape.
- Use the standard library's `requests`, `json`, `yaml` (PyYAML), `subprocess`, and `pathlib` without looking things up.
- Read a Jinja2 template and understand what it will produce when given a context.
- Use a virtual environment so the scripts they write today still work in six months.
- Use an LLM to generate Python for a one-paragraph intent, and verify the result with the generate-then-verify loop the article anchors on.
- Recognize when Python is the right tool and when [[article-09-ansible]] (declarative state) or [[article-13-terraform]] (declarative provisioning) is the right tool instead.

## Outline

1. **Why Python.** Every network-automation tool either *is* Python ([[article-09-ansible]], `pynetbox`, `nornir`) or has a Python client. The reader who can write a hundred lines of competent Python can integrate any of them.
2. **The minimal language.** Variables, types, control flow, functions, classes-as-namespaces. Strict subset; no metaclasses, no decorators beyond `@property`, no async. The article teaches the bottom 20% that handles 90% of network-work scripts.
3. **The four imports you'll reach for daily.** `json`, `yaml` (PyYAML), `requests`, `pathlib`. One canonical use per import. The "what does this do" pattern, not the API reference.
4. **Virtual environments and dependency hygiene.** `venv`, `requirements.txt`, `pip`. One paragraph; the reader needs the muscle memory, not the philosophy. Forward-pointer to Article 11 (Docker) for the cases where venv is not enough.
5. **Jinja2 templating.** The templating language every network-automation tool uses to produce configs. Variable interpolation, `for`, `if`, filters. Worked example: a YAML inventory → an FRR config block via Jinja2. This is the bridge from Article 7 (structured data) to Article 9 (Ansible).
6. **Calling external commands.** `subprocess.run` with `check=True` and `capture_output=True`. Parsing JSON output from `ip -j`, `nft -j list ruleset`, and friends. The pattern from [[article-01-linux-for-network-engineers]] now becomes the foundation of a script.
7. **Error handling, just enough.** `try`/`except` for the I/O cases you'll actually encounter. Logging via `logging` with one canonical setup. No exception-class-design discussions.
8. **The generate-then-verify loop.** The article's pedagogical anchor. The reader writes a script the agent helped generate, runs it against fixture data, asserts the output matches expected — and only then runs it against real data. This loop is the safety net for everything the rest of the series builds on top of.
9. **How LLM agents fit here.** Python is the agent's strongest generative domain — vastly more public training data than any networking-specific syntax. The reader's job is to make the verification cheap, not to write less Python themselves. Two specific moves: (a) generate-from-intent (paste the data shape and the goal, get a script; verify with fixture data); (b) explain-from-code (paste a script someone else wrote, get a walk-through; verify by predicting what it will do, then running it).

## Lab

Reader writes a script (with LLM help) that:

1. Reads a YAML device inventory.
2. For each device, fetches `ip -j route show` from a fixture (or live target if the reader has one available).
3. Joins the routing data back to the inventory.
4. Emits a Markdown report.

The lab uses pytest with a small fixture suite so the reader practices the **generate-then-verify** loop end to end: the agent generates, the test suite verifies, the reader iterates.

Optional extension: run the same logic against a live container from the [[article-04-routing-daemons]] lab via `subprocess`.

## Foundational material needed

| Prerequisite | Covered where | Notes |
|---|---|---|
| Shell fluency | **External** | |
| Linux command-line tooling | [[article-01-linux-for-network-engineers]] | `subprocess` calls JSON-emitting `ip`, `nft`, `ss` |
| YAML / JSON fluency | [[article-07-structured-data]] | Direct prerequisite |
| Git workflow | [[article-06-git]] | The lab's example repo lives in version control |

## Assumed networking knowledge

- Generic "I have written shell scripts before" comfort
- Comfort with the idea of templating configs (Jinja2 will feel familiar to anyone who has written ERB, Go templates, or even a Word mail-merge)
- Familiarity with REST as a category, even if the reader has never made an API call from code

## How LLM agents fit here

Python is where the agent moves from translator (Article 1) and generator (Articles 4–5) to **collaborator on real work**. The reader is writing scripts they would not have written by hand, faster than they could have written them. The article's job is to make the verification habit survive that speed.

The generate-then-verify loop is the operational form of the verification habit the series has been building since Article 1. The agent writes a function; the reader writes (or asks the agent to write) the fixture and the assertion; the test runs; the reader reads the diff between expected and actual; the reader decides whether to ship. The loop is fast enough to use on every change and rigorous enough to catch the obvious failure modes.

The article also names the failure mode the reader will hit: the agent will produce *plausible* code that does the wrong thing. The defense is the test suite, not careful reading. This is the moment the series stops pretending careful reading scales and starts teaching the reader to invest in verification machinery.

## Concepts and entities introduced

- [[python]]
- The "generate-then-verify loop" as a named pattern referenced throughout the rest of the series

## Open questions

- **Python version.** The lab will standardize on 3.11+ (matches Ubuntu 22.04 / Debian 12 defaults). Worth flagging because some `pynetbox` examples in the wild use older syntax.
- **`requests` vs `httpx`.** `requests` is still the canonical answer for the audience; `httpx` is better but unfamiliar. Default to `requests` and mention `httpx` as the modern successor.
