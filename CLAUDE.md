# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

This is the public **official website for Masters International School (MIS)** — a static
Hugo site whose Git repository is the single source of truth. Content is edited by humans
via Decap CMS and by an AI (nanobot) via MCP; both ultimately produce Git commits that
GitHub Actions builds and deploys to GitHub Pages. See the design doc under
`docs/superpowers/specs/` for the full architecture.

---

## 宪法 / Constitution (HARD CONSTRAINTS — non-negotiable)

These are binding rules. Do not violate them or work around them without explicit user approval.

### AWS — always use the `mis` profile
- **Every `aws` CLI call MUST pass `--profile mis`.** No exceptions. Never use the default profile.
- The `mis` profile's default region is **`ap-southeast-7` (Bangkok)**, which has **no Lightsail
  endpoint** — always pass `--region` explicitly for Lightsail and region-scoped services.
- Known resources live in **`ap-southeast-1` (Singapore)**.

Example:
```bash
aws lightsail get-instances --profile mis --region ap-southeast-1 --output table
```

---

## Verified infrastructure (do not re-discover)

### AI / ops host — Lightsail `mis-ops-bot`
- Region `ap-southeast-1`, public IP `18.141.228.49`, Ubuntu, bundle `nano_3_0` (2 vCPU / 0.5 GB RAM).
- Open ports: **1022 (SSH — not 22)**, 80, 443.
- Role: runs the control-plane bots (nanobot + GitHub MCP + Decap auth proxy). Does NOT host the
  website itself (the site is static on GitHub Pages). Load is light; 0.5 GB RAM is tight — use
  swap or bump the bundle if memory-constrained.

### Identity — Zitadel (existing, reused)
- Issuer: `https://auth.mastersinternationalschool.org`, org `mis` (`375822041443532802`).
- CMS roles already provisioned: `cms-superadmin`, `cms-editor`, `cms-admissions`, `cms-hr`
  (plus `staff`, `it-admin`, `parents`).
- Automation service account `mis-automation` (ORG_OWNER) + long-lived PAT.
- Config lives in the sibling repo `/Users/david/projects/outsources/mastersinternational.org`
  (`zitadel/website-oidc-resources.md`). Secrets are gitignored there — never copy them here.

### Repository & hosting
- GitHub repo: **`it-of-mis/website`** (public).
- Hosting: **GitHub Pages**, built by **GitHub Actions** (official Hugo workflow).
- Languages: **`en` (primary)**, `zh`, `th`; `zh-Hant` optional/reserved.

---

## Architecture (Less is More — Git is the single source of truth)

Two write paths converge on one Git repo; one delivery path leaves it:

- **Data layer** — the Git repo (all Markdown content, config, history).
- **Human track** — Decap CMS (static SPA at `/admin`) → commits via GitHub API.
- **AI track** — nanobot (MCP host) + GitHub MCP → commits via GitHub API.
- **Delivery** — GitHub Actions builds Hugo → deploys `public/` to GitHub Pages.

### Identity model (both tracks share one shape)
- **Write credential to GitHub:** a single GitHub **bot** credential (GitHub App / fine-grained
  PAT), shared by the Decap auth proxy and nanobot's GitHub MCP. GitHub-level identity is
  intentionally a machine, never a person.
- **Who is operating:** a **Zitadel SSO** session gates BOTH entry points (Decap `/admin` and the
  nanobot UI), authorized by `cms-*` roles.
- **Attribution:** the operating user's Zitadel identity is stamped into each commit
  (author/trailer/message), even though the push uses the shared bot credential.
- Do **not** give individual users their own GitHub tokens for the MCP — that would require every
  staff member to have a GitHub account and defeats the SSO model.

### i18n content layout (Hugo native, multiple files)
Content is flat under `content/`, language by filename suffix:
`content/<section>/<slug>.en.md`, `.zh.md`, `.th.md`. Decap `i18n` is configured with
`structure: multiple_files`, locales `[en, zh, th]`, `default_locale: en`.
