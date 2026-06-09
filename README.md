# Modern Network Engineer

I'm writing this series as a refresher on modern networking constructs — things I've worked with in labs or wanted to dig into more, but never got around to and lost some of that knowledge. With each article I try to build a container (or multiple) you can pull, along with exercises you can do inside the container to practice the concept.

I'm writing for the people stuck in the legacy networking stack: buy Cisco, connect Cisco, configure Cisco, follow Cisco trends. The people with a CCNA or CCNP they've kept current, but who haven't adopted new industry technologies and feel like they're getting left behind when searching for a job.

I'm also exploring where generative AI fits into network engineering throughout the series — I've built agents to do some work for me and done a fair amount of interactive troubleshooting and script writing in my roles, and I want to focus that on each of these primitives and show how it can be useful for other people.

I've included Git, Ansible, and Python, but I'm only pointing to resources and giving labs for those. They've been covered to death and I don't think I can add much beyond giving some practice exercises.

Note that much of the content is written with the help of AI. I used Obsidian as a knowledge repo and linked Claude to it to manage and query the repo, keep things linked and organized, write outlines, and write initial drafts. If you find something inaccurate or think a topic could be presented better, please message me or write your own and backlink it. I'll probably review PRs for corrections on GH, but no promises.

I plan to host the series here on GitHub as the primary source of truth and cross-post to LinkedIn. I'm letting it grow organically. I hope this finds you when you need it.

---

## Articles

| # | Article | Labs |
|---|---------|------|
| 1 | [Linux for Network Engineers](wiki/article-01-linux-for-network-engineers.md) | [Lab A01](labs/lab-a01-translation/) |
| 2 | [Interfaces, Namespaces, and Topologies in Linux](wiki/article-02-interfaces-namespaces-topologies.md) | [Lab A02](labs/lab-a02-topologies/) |
| 3 | [Common Network-Admin Tasks, Done in Base Linux](wiki/article-03-common-network-admin-tasks.md) | [Lab A03](labs/lab-a03-admin-tasks/) |
| 4 | [Routing Daemons (Linux as a Router)](wiki/article-04-routing-daemons.md) | [Lab A04](labs/lab-a04-routing/) |

## Containers

Each article ships a container with the tools and namespaces needed for its labs. Pull and run the container for whichever article you're working through:

```bash
docker compose -f containers/article-NN/docker-compose.yml run --rm lab
```
