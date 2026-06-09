
# Article 06 — Git and Collaborative Workflows

The Foundation cluster's version-control article. The reader has Linux fluency and a topology they can build; this article gives them the workflow that replaces "save config" on a router with a real change-management primitive.

The framing is **workflow-first**, not command-first. Anyone can `git add` and `git commit`; what the network engineer needs is the muscle memory of branching, peer review, and merge as a daily habit — plus the framing for why the audit trail is the safety net that earlier articles' "discipline replaces IOS safety features" line was promising. This article is where the discipline starts.

## Expected outcome

The reader finishes the article able to:

- Initialize a repository, commit changes, push to a remote, and recover from the four most common stuck states (detached HEAD, conflicting merge, accidental commit on main, force-push regret).
- Run a branch-and-PR workflow end-to-end: feature branch, commits, PR, review comments, merge.
- Read a diff and a `git log` graph fluently enough to reconstruct what a change actually did.
- Write commit messages and PR descriptions that an LLM reviewer can use as context.
- Position Git as the operational replacement for the `archive` / `configure replace` / TACACS-accounting trio that the legacy stack provided.
- Use an LLM as a writing assistant for commit messages and a first-pass reviewer for diffs, while keeping the verification habit intact.

## Outline

1. **Why this article exists.** The audit-trail promise from [[article-01-linux-for-network-engineers]] (Git replaces `archive`; code review replaces TACACS per-command accounting; CI replaces `commit confirmed`) starts being concrete here. The reader has been told the discipline is real; now they learn the daily moves that make it work.
2. **The mental model.** A commit is a snapshot; a branch is a pointer; a merge is a reconciliation. Three sentences, three diagrams, no jargon. The reader's intuition from "save config" is the wrong anchor and needs replacing.
3. **The minimal command set.** `init`, `clone`, `status`, `add`, `commit`, `diff`, `log`, `branch`, `checkout`, `merge`, `push`, `pull`, `fetch`. Each with one canonical use and one "you'll see this and wonder" example. No alias gymnastics; the reader can build that habit later.
4. **Branching and pull-request workflow.** The actual day-to-day: create a feature branch, make changes, push, open a PR, address review comments, merge. The PR is the unit of change-management; the merge is the apply-to-production moment in everything that comes later in the series.
5. **The four stuck states and how to recover.** Detached HEAD, conflicting merge, accidental commit on main, force-push regret. The reader will hit each at least once; naming them up front converts panic into a recipe.
6. **Reading history.** `git log --oneline --graph`, `git blame`, `git show`, `git diff branch1..branch2`. The reader needs to be able to reconstruct "what changed and why" from the repo alone, because in modern operations the repo *is* the audit log.
7. **`.gitignore`, `.gitattributes`, and the line-ending trap.** One paragraph of gotchas. Vendor configs with CRLF line endings vs Linux configs with LF will bite anyone who skips this.
8. **The audit-trail framing.** This is the article's anchor. Per-commit attribution, per-PR review, per-merge timestamp. Compared to: `archive`, `configure replace`, TACACS per-command accounting. The Linux stack is *coarser* per-command and *richer* per-change. Name the trade honestly so a regulated-shop reader can decide where their requirements actually live.
9. **GitHub vs GitLab vs self-hosted Gitea.** One paragraph. The series uses GitHub by default because the reader is likely to encounter it; the workflow is identical on GitLab or Gitea. Mention that the [[github-actions]] tooling assumed by [[article-22-ci-cd]] is GitHub-specific but the underlying patterns transfer.
10. **How LLM agents fit here.** First use of the agent as a *writing assistant* and *first-pass reviewer*. Commit messages and PR descriptions are well-suited to LLM generation because they have a tight structure and a clear context (the diff itself). Diff review is well-suited to LLM first-pass because the agent catches the obvious issues a tired reviewer misses (a typo'd interface name, an inconsistent metric, a leftover debug print) and leaves the harder judgment calls to the human. The verification habit: read what the agent generated against the actual diff before clicking Merge.

## Lab

The reader creates a small repository for a network-config exercise (e.g., a directory of FRR config snippets carried over from [[article-04-routing-daemons]]'s lab). They:

1. Initialize the repo, make a first commit.
2. Branch, change a config, commit, push to a sandbox remote (a local bare repo on the same host, or GitHub).
3. Open a PR, leave a review comment on themselves, merge.
4. Deliberately create one of the four stuck states (force-push over their own work) and recover using `git reflog`.
5. Hand an LLM a one-line intent and the staged diff; ask it to write a commit message; verify against the diff and commit.
6. Hand an LLM a multi-file diff from the lab repo; ask for a first-pass review; correlate its observations with `git diff` output.

The lab uses a local bare repo by default so the reader does not need a GitHub account to complete the article. An optional GitHub variant of step 2 is documented for readers who want to practice the full hosted workflow.

## Foundational material needed

| Prerequisite | Covered where | Notes |
|---|---|---|
| Shell fluency | **External** | The reader is expected to be comfortable in a terminal |
| Linux command-line tooling | [[article-01-linux-for-network-engineers]] | Pipes, redirection, basic file ops |
| Any prior Git exposure | **External, optional** | Not required; this article assumes none |

## Assumed networking knowledge

See [[assumed-networking-knowledge]].

- Change-management concepts at a generic level (what a change window is, why peer review exists)
- The legacy `archive` / `configure replace` / TACACS accounting model — used as the comparison point in §8

## How LLM agents fit here

This is the article where the agent's role expands from *translator* (Article 1) and *generator* (Article 4) to *writing assistant* and *first-pass reviewer*. Two specific moves:

**Commit-message and PR-description generation.** Given a staged diff and a one-line intent, the agent produces a Conventional-Commits-style message and a PR description that explains the *why*. This works because the diff is concrete context and the output format is constrained. The verification loop: read the agent's message against the diff; if a reasonable reviewer would learn what the change does from the message, accept; if not, edit.

**First-pass diff review.** Hand the agent a diff and ask "what would a careful reviewer flag here." The agent catches the easy stuff (typos, inconsistent variable names, unused imports, off-by-one numbers, the same change applied in five places except one) and leaves judgment calls to the human. This is the moment the agent stops being purely your tool and starts being a collaborator who pre-screens work for you — a power level worth naming explicitly because it is also the level at which an unverified agent can do real harm.

The verification habit from earlier articles becomes load-bearing: the agent's review is *advisory*, the merge button is *yours*. The agent never merges anything in this series — tool-using agents arrive in [[article-12-containerlab]], and even then the merge boundary stays human until [[article-23-mcp]] revisits it deliberately.

## Concepts and entities introduced

- [[git]]
- The "audit trail as discipline" framing — referenced forward by [[article-14-netbox]] (source-of-truth as the institutional audit log) and [[article-22-ci-cd]] (the merge as the deploy trigger)

## Open questions

- **Local bare repo vs GitHub for the lab.** Local is friction-free and works offline; GitHub gives the reader exposure to PR-review UI that matters later. Probably default to local with a documented GitHub variant.
- **Conventional Commits as a hard convention or a suggestion.** The series benefits from convention here because [[article-22-ci-cd]] keys some CI behavior off commit-message prefixes. Probably soft-enforce in the article body and hard-enforce in the lab's example repo.
