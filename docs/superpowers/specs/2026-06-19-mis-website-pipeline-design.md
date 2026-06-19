# MIS Website — Control-Plane Pipeline (v1) — Design

> Date: 2026-06-19 · Status: approved-pending-review · Owner: david (dawei101)
> Repo: `it-of-mis/website` (to be created, public)

## 1. Goal

Stand up an **empty Hugo skeleton site** whose **Git repo is the single source of
truth**, and wire two write paths plus one delivery path onto it so the full
"edit → commit → publish" loop works end to end:

- **Human track** — Decap CMS edits content and commits via the GitHub API.
- **AI track** — the existing `website` nanobot edits content via an MCP and commits.
- **Delivery** — GitHub Actions builds Hugo and deploys to GitHub Pages.

This is **plumbing only**. We are NOT migrating any real website content from the
current Payload/Postgres site in this project — just enough sample content to
exercise the loop. The Payload→Hugo content migration and the parents/staff
portal are explicitly out of scope (see §9).

Framing: this is a re-platforming step away from the database-backed CMS toward a
Git-as-SSOT, database-free architecture ("Less is More"). The existing `website`
nanobot is **repointed** from the Payload CMS MCP to operate this Git repo instead.

## 2. Hard constraints (see CLAUDE.md "宪法")

- **AWS:** every `aws` call uses `--profile mis`; pass `--region` explicitly
  (profile default region `ap-southeast-7` has no Lightsail endpoint; resources
  live in `ap-southeast-1`).
- **Identity:** reuse the existing **Zitadel** IdP (`auth.mastersinternationalschool.org`,
  org `mis`) and its already-provisioned `cms-*` roles. Never copy Zitadel/PAT
  secrets into this repo.
- **Bots framework:** reuse the existing `bots/` repo + `deploy.sh` workflow and
  the Go **orchestrator** (sibling repo `outsources/mastersinternational.org`).
  Do not fork a parallel bot system.

## 3. Architecture

Two write paths converge on one Git repo; GitHub Actions delivers from it.

| Layer | Reuse / New | Detail |
|---|---|---|
| Content / SSOT | 🆕 `it-of-mis/website` (public) | Hugo skeleton; i18n `en`(primary)/`zh`/`th`; sample content only |
| Delivery | 🆕 GitHub Actions → Pages | Official Hugo workflow; custom domain wired LAST |
| Human track | 🆕 Decap CMS at `/admin` | `editorial_workflow` (draft → PR); GitHub backend via auth proxy |
| Decap auth | ♻️ Zitadel via orchestrator | New OAuth endpoint on the existing Go orchestrator: OIDC+PKCE → `cms-*` gate → hands Decap the bot token |
| Write credential | 🆕 fine-grained PAT (v1) | Scoped to `it-of-mis/website`; shared by the Decap proxy and the nanobot GitHub MCP. Upgrade path: GitHub App |
| AI track | ♻️ existing `website` bot | MCP `mis-cms` → **GitHub MCP** on the new repo; model stays `anthropic/claude-sonnet-4.6` via OpenRouter; "drafts only" guardrail kept |
| Conversational entry | 🆕 WhatsApp channel | Multi-user; `whatsapp:<phone>` → person → commit author |
| TLS / reverse proxy | ♻️ Caddy on `mis-ops-bot` | Existing stack |
| Host | ♻️ Lightsail `mis-ops-bot` | Singapore; runs orchestrator + `website` bot only |

### 3.1 Identity model (both tracks share one shape)

- **Write credential to GitHub** = one machine credential (fine-grained PAT v1),
  shared by the Decap auth proxy and nanobot's GitHub MCP. GitHub-level identity
  is intentionally a machine, never a person.
- **Who is operating** = an authenticated session, gated by `cms-*` roles:
  - Decap: Zitadel OIDC via the orchestrator.
  - nanobot: the WhatsApp sender, identified as `whatsapp:<phone>`.
- **Attribution** = the operator's identity is stamped into each commit
  (author/trailer/message). The agent reads `USER_ID`/`CHANNEL` from the session
  (existing AGENTS.md convention) and maps it to a person.
- We do NOT give individual users their own GitHub tokens for the MCP.

### 3.2 i18n content layout (Hugo native, multiple files)

Flat under `content/`, language by filename suffix:
`content/<section>/<slug>.en.md`, `.zh.md`, `.th.md`. Decap `i18n`:
`structure: multiple_files`, `locales: [en, zh, th]`, `default_locale: en`.
`zh-Hant` is reserved (config kept ready) but not enabled in v1.

### 3.3 "Drafts only" → editorial workflow

The `website` bot's load-bearing guardrail ("drafts only, never publish/delete
without a human") maps onto GitHub mechanics: the AI commits to a draft branch /
opens a PR; a human merges. Decap uses `editorial_workflow` so human edits also
flow draft → PR → merge → publish. Merging to the default branch is the only
thing that triggers a production deploy.

## 4. Phases & acceptance criteria

### Phase 1 — Hugo skeleton + repo + Pages
- `gh repo create it-of-mis/website` (public); push Hugo skeleton with i18n and
  1–2 sample content types (e.g. a `news` list + a couple of singleton pages).
- GitHub Actions builds Hugo and deploys to Pages.
- **Done when:** a push to the default branch redeploys the site on the Pages
  default domain, with `en`/`zh`/`th` routes rendering.

### Phase 2 — Decap + Zitadel auth proxy (human loop)
- Add `/admin` (Decap `config.yml` with i18n collections + `editorial_workflow`).
- Add an OAuth endpoint to the orchestrator that authenticates via Zitadel
  (OIDC+PKCE, reusing the orchestrator's existing auth module), checks for a
  `cms-*` role, and returns the bot PAT to Decap in the format Decap expects.
- **Done when:** a `cms-editor` logs into `/admin` via school SSO, edits content,
  it lands as a PR, and merging redeploys the site. No GitHub account needed by
  the editor.

### Phase 3 — Repoint `website` bot + WhatsApp + author binding (AI loop)
- Repoint the `website` bot config: replace MCP `mis-cms` with a GitHub MCP
  targeting `it-of-mis/website` (bot PAT).
- Add a WhatsApp channel to the bot; add a phone→person identity map (name,
  email, Zitadel role) so unknown senders are rejected and known senders get
  attributed.
- Update the bot persona so commits carry the operator's author/trailer and stay
  "drafts only" (PRs, not direct publishes).
- Remove the `ops` bot (see §5).
- **Done when:** an authorized person messages the bot on WhatsApp, the bot opens
  a PR with content changes attributed to that person, and a human merge
  redeploys.

### Final (manual, when ready) — DNS cutover
Point `www.mastersinternationalschool.org` at GitHub Pages and set the custom
domain. Register the orchestrator OAuth callback + any bot endpoints in Zitadel
redirect URIs. Done by hand at cutover, not during P1–P3.

## 5. Decommission the `ops` bot

Scope reduction (confirmed): keep only the `website` bot.
- In `bots/`: remove `ops/`, `systemd/nanobot-ops.service`, the `OPS_*` vars in
  `.env.example`, and `ops` from the `deploy.sh` bot loop.
- On the box: `systemctl stop` + `disable` + remove the unit for `nanobot-ops`.
This is a Phase-3 cleanup task, performed with explicit confirmation (it stops a
running service on the host).

## 6. Credential automation boundary

Automatable now via the `dawei101` `gh` token (`repo` scope): repo creation,
Pages enablement, Actions workflow, repo secrets, branch protection, labels,
skeleton push. **Not** headless-automatable: minting the API token itself —
GitHub provides no API to create a PAT, and GitHub App keys require a browser
manifest flow. v1 therefore uses a **fine-grained PAT** created once in the
browser (single manual step, exact permissions given at execution time), pasted
into `bots/.env`. Everything else is scripted.

## 7. Components to build

1. Hugo skeleton (config, i18n, minimal layouts, sample content, `/admin`).
2. GitHub Actions Hugo→Pages workflow.
3. Decap `config.yml` (i18n + editorial_workflow + GitHub backend `base_url` → orchestrator).
4. Orchestrator OAuth endpoint (Zitadel → `cms-*` gate → return bot token).
5. `website` bot config change (GitHub MCP) + WhatsApp channel + phone→person map + persona update.
6. `ops` bot removal.

## 8. Risks / assumptions to verify in the plan

- **WhatsApp channel support:** nanobot v0.2.1's native WhatsApp channel is
  assumed from the `<channel>:<user_id>` session convention. If absent, add a
  thin WhatsApp Cloud API ↔ nanobot websocket bridge on the box. Verify first.
- **Org repo-create permission:** `dawei101` must be able to create repos in the
  `it-of-mis` org. Verify with the actual `gh repo create`.
- **Box RAM:** `mis-ops-bot` is 0.5 GB. Orchestrator + `website` bot + GitHub MCP
  should fit (removing the `ops` bot helps), but add swap or bump the bundle if
  memory-constrained.
- **Private-repo Pages:** repo is public, so Pages needs no paid plan.

## 9. Out of scope (v1)

- Migrating real content from Payload/Postgres to Hugo.
- The parents/staff portal (stays on the existing Next.js app).
- `zh-Hant` locale (config reserved, not enabled).
- Full site design/theme — skeleton/minimal layouts only.
- DNS cutover to the production domain (manual, final step).
