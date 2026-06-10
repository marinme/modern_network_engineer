# Claude Code entrypoint — modern_network_engineer (public repo)

This repo is the **public-facing output** of a private Obsidian vault at
`../networking_articles/`. It is not edited directly. Content arrives here
via `../networking_articles/publish.sh`, which syncs a filtered subset of
the vault and pushes it to GitHub.

---

## What this repo contains

| Path | Source | Notes |
|---|---|---|
| `wiki/article-*.md` | `networking_articles/wiki/article-*.md` | Vault frontmatter stripped on sync |
| `labs/` | `networking_articles/labs/` | Full copy — walkthroughs, assets, test suites |
| `containers/` | `networking_articles/containers/` | Full copy — Dockerfiles, compose files |
| `README.md` | `networking_articles/README.md` | The public landing page |

Everything else in the vault — `raw/`, wiki internals (`log.md`, `index.md`,
source summaries, concept pages), `SCHEMA.md`, `CLAUDE.md`, `.obsidian/` —
is private and never appears here.

---

## What you must not do

- **Do not edit article content here.** `wiki/article-*.md` files are
  overwritten on every publish run. Any edits made directly in this repo
  will be silently wiped the next time `publish.sh` runs. All article edits
  belong in the vault.
- **Do not edit lab walkthroughs or test scripts here.** Same reason — they
  are overwritten from `networking_articles/labs/` on every sync.
- **Do not edit container files here.** Overwritten from
  `networking_articles/containers/` on every sync.

---

## What you can do here

- **Edit `README.md`** — the public landing page. This file is copied from
  the vault on each publish, so make the canonical edit in
  `networking_articles/README.md` and let publish.sh carry it over. If you
  edit it here directly, note that it will be overwritten on the next sync
  unless the vault copy is also updated.
- **Add repo-level files** that have no vault equivalent: `LICENSE`,
  `.github/` workflows, `CONTRIBUTING.md`, issue templates, etc. These live
  only in this repo and are not touched by publish.sh.
- **Review what was published** — check that article frontmatter was
  stripped, labs are intact, and containers are present.

---

## How to trigger a publish

From the vault directory:

```bash
cd ../networking_articles
./publish.sh
```

`publish.sh` will:
1. Strip YAML frontmatter from articles and write them into this repo's `wiki/`
2. Rsync `labs/` and `containers/` in full (with `--delete` so removals propagate)
3. Copy `README.md`
4. Commit if anything changed, referencing the vault's HEAD SHA
5. Pull then push to `origin main`

---

## Relationship to the vault

```
networking_articles/     ← private vault (Obsidian + agent workspace)
  publish.sh             ← the sync script
  wiki/article-*.md      ← source of truth for articles
  labs/                  ← source of truth for labs
  containers/            ← source of truth for containers
  README.md              ← source of truth for the landing page

modern_network_engineer/ ← this repo (public GitHub)
  wiki/article-*.md      ← synced copy, frontmatter stripped
  labs/                  ← synced copy
  containers/            ← synced copy
  README.md              ← synced copy
  CLAUDE.md              ← this file (lives only here, not in vault)
```

If you need to make a content change, go to the vault. If you need to make
a repo-infrastructure change (CI, license, contributing guide), make it here.
