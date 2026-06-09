
# Article 11 — Containers and Docker for Network Engineers

The article that converts containers from "developer magic" to "infrastructure the reader owns." Containers underpin almost every modern network tool; a network engineer who can't work with them is locked out of the ecosystem.

## Expected outcome

The reader finishes the article able to:

- Run, build, and troubleshoot Docker containers.
- Articulate the difference between images and containers, what container networking actually does, and where volumes fit.
- Containerize a small network tool of their own.
- Recognize containers as the **execution-isolation primitive** that makes the rest of the series — and later, agent-driven workflows — possible.

## Outline

1. **Why this article exists.** Containers are not a developer-only concern. [[netbox]], [[prometheus]], [[grafana]], [[containerlab]], CI runners, network simulators — all containers. Working with them is table stakes.
2. **The mental model.** An image is a frozen filesystem plus metadata; a container is a running process with its own namespaces (the same Linux namespaces from Article 1). This is a small conceptual unlock — containers are not VMs, they're Linux processes with isolation.
3. **`docker run`, `docker ps`, `docker logs`, `docker exec`.** The minimum useful command surface.
4. **Container networking modes.** Bridge, host, none, user-defined networks. Walk through what each does using `ip` and `tcpdump` from Article 1 to see the bridge interface, the veth pairs, the NAT rules.
5. **Volumes and persistence.** Why containers are ephemeral by default and how to opt out where it matters.
6. **Building an image.** `Dockerfile` essentials: base image, `RUN`, `COPY`, `CMD`, layer caching. Enough to containerize a script.
7. **The container ecosystem signal.** Docker Hub, image tags, multi-stage builds, image security basics. Just enough to be a critical consumer of public images.
8. **Lab walkthrough.** Containerize the drift detector from Article 9. Run it from a container against a cEOS topology.
9. **How LLM agents fit here.** Execution isolation as a guardrail primitive — the first half of the sandbox pattern that lands fully in Article 11.

## Lab

Reader takes the drift detector from Article 9 and:

1. Writes a `Dockerfile` that bases on `python:3.12-slim`, installs dependencies, copies the script.
2. Builds the image, runs it, sees the same output as bare Python.
3. Mounts the baseline-configs directory as a volume.
4. Pushes the image to a local registry (or skips, if no registry is set up).
5. Inspects the container's network interfaces with `docker exec` + `ip addr`, ties back to Article 1.

## Foundational material needed

| Prerequisite | Covered where | Notes |
|---|---|---|
| Linux fluency, namespaces | **[[article-01-linux-for-network-engineers]]** | Containers *are* namespaces with branding; the Article 1 grounding makes this article click |
| Git for Dockerfiles | **[[article-06-git]]** | |
| Python script to containerize | **[[article-08-python]]** + **[[article-10-rest-apis]]** | The drift detector from Article 9 is the lab subject |
| Containerlab as a downstream consumer | **[[article-12-containerlab]]** — *consumed next* | Article 10 prepares the ground; Article 11 builds on it |

Article 10 is the pivot point: every later article assumes the reader can run a container. The Article 1 + Article 10 pair is the substrate everything from Article 11 onward stands on.

## Assumed networking knowledge

External prerequisites the reader brings in. See [[assumed-networking-knowledge]] for the series-wide picture.

- Bridge, NAT, veth (revisited from [[article-01-linux-for-network-engineers]] but assumed in the prose)
- Linux network namespaces as a routing/isolation primitive
- Existence and rough purpose of network simulators and device emulators
- Management plane vs data plane as a real distinction

## How LLM agents fit here

This article introduces **execution isolation as a guardrail primitive**. The reader already met audit-trail-as-safety-net in Article 6; here they meet the second pillar: agents (and agent-generated code) should run somewhere the worst-case outcome is bounded. Containers are not the only way to bound execution, but they are by far the most common way the reader will encounter — locally, in CI, in production tooling, and inside [[article-12-containerlab]].

The teaching is concrete, not theoretical. When an agent writes a Python script the reader is going to run, *where* the reader runs it matters as much as *what it does*. Running it on the reader's laptop with full credentials and a route to production is the bad shape. Running it in a container with only the env vars and network reachability it actually needs is the good shape. The agent doesn't need to be told to be careful; the environment doesn't let it be careless. This is the same principle Article 11 will generalize into the full sandbox pattern.

Three concrete moves the article should teach for working with an agent here:

- **Have the agent write the Dockerfile alongside the script.** Pair-programming pattern from Article 7 extends naturally: the agent produces the script *and* the Dockerfile *and* a minimal `docker run` command. The reader reviews all three. The container becomes the verification surface — if it builds and runs to completion in isolation, the reader has cheap evidence the script is at least self-contained.
- **Constrain the container's capabilities deliberately.** No `--privileged`. No `--network host` unless required. Mount only the volumes the script actually needs. Drop credentials in via env vars at run time, never bake them into the image. The agent should be coached to propose these constraints up front; the reader should be coached to push back when the agent over-grants.
- **Treat container troubleshooting as a place where the agent earns its keep.** "Why is my container hanging on startup," "why can my container reach Google but not my cEOS lab," "why is my image 3GB" — these are exactly the kinds of papercuts an LLM resolves in seconds with a tcpdump output, a `docker inspect` dump, or a Dockerfile diff. Reader observes, agent diagnoses, reader verifies.

The forward-looking note: containers give the reader the *ingredient* for sandboxing. [[article-12-containerlab]] composes containers into the lab pattern that the rest of the series — and every agentic workflow that touches a device — depends on. The reader leaves Article 10 with one container running a script; they leave Article 11 with twelve containers acting as a network fabric.

## Concepts and entities introduced

- [[docker]]

## Open questions

_(none yet)_
