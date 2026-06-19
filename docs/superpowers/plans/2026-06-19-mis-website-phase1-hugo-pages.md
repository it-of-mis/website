# MIS Website — Phase 1: Hugo Skeleton + GitHub Pages — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up an empty, multilingual Hugo skeleton site in a new public repo `it-of-mis/website` that builds locally and auto-deploys to GitHub Pages on every push to `main`.

**Architecture:** A themeless Hugo site with hand-written minimal layouts and Hugo-native i18n via filename suffixes (`.en.md`/`.zh.md`/`.th.md`, "translation by filename"). A repeatable `scripts/check-build.sh` is the build/i18n test, run both locally and in CI. A GitHub Actions workflow builds with the Pages-provided `baseURL` and deploys the artifact, so a later DNS/custom-domain cutover needs no code change.

**Tech Stack:** Hugo (extended), GitHub Actions, GitHub Pages, `gh` CLI.

## Global Constraints

- Repo: **`it-of-mis/website`**, **public** (Pages on a public repo needs no paid plan).
- Default branch: **`main`**. No branch protection in Phase 1 (it would block our own pushes; editorial-workflow PRs arrive in Phase 2).
- Languages: **`en` (primary, served at site root), `zh`, `th`**. `defaultContentLanguageInSubdir = false`. `zh-Hant` is reserved — do NOT add it in Phase 1.
- i18n mechanism: **translation by filename** (`<name>.<lang>.md`), matching Decap's planned `structure: multiple_files`.
- `baseURL` for deploys comes from the Pages action output at build time; the value in `hugo.toml` is a local-only fallback. Do NOT hardcode the production domain into the build.
- AWS (if ever needed): every `aws` call uses `--profile mis` with an explicit `--region` (see CLAUDE.md "宪法"). Not expected in Phase 1.
- `CLAUDE.md` and `docs/superpowers/` already exist in the working dir and must be committed as part of Task 1.

---

### Task 1: Git repo + buildable multilingual Hugo skeleton

**Files:**
- Create: `.gitignore`
- Create: `hugo.toml`
- Create: `layouts/_default/baseof.html`
- Create: `layouts/index.html`
- Create: `layouts/_default/list.html`
- Create: `layouts/_default/single.html`
- Create: `content/_index.en.md`, `content/_index.zh.md`, `content/_index.th.md`
- Create: `content/news/_index.en.md`, `content/news/_index.zh.md`, `content/news/_index.th.md`
- Create: `content/news/welcome.en.md`, `content/news/welcome.zh.md`, `content/news/welcome.th.md`
- Create: `content/about.en.md`, `content/about.zh.md`, `content/about.th.md`
- Test: `scripts/check-build.sh`

**Interfaces:**
- Produces: a committed local git repo on branch `main`; a `hugo` build that emits `public/index.html` (en), `public/zh/index.html`, `public/th/index.html`, and `public/news/welcome/index.html` per locale. `scripts/check-build.sh` exits 0 on a correct build (consumed by Task 2's CI and Task 3's verification).

- [ ] **Step 1: Verify Hugo extended is installed, capture the version**

Run: `hugo version`
Expected: a line like `hugo v0.1xx.x ... extended`. Record the exact version (e.g. `0.140.2`) — Task 2 pins the CI to it.
If missing: `brew install hugo` then re-run.

- [ ] **Step 2: Initialize git on `main`**

```bash
cd /Users/david/projects/it-of-mis/website
git init -b main
```
Expected: `Initialized empty Git repository`.

- [ ] **Step 3: Write `.gitignore`**

```gitignore
# Hugo
/public/
/resources/_gen/
/.hugo_build.lock

# OS
.DS_Store
```

- [ ] **Step 4: Write `scripts/check-build.sh` (the test — it must FAIL now)**

```bash
#!/usr/bin/env bash
# Build the site and assert the multilingual routes + content exist.
# Used locally and in CI. Run from repo root.
set -euo pipefail

# Build unless the caller already produced public/ (CI builds with the Pages
# baseURL first, then runs this verify-only with SKIP_BUILD=1 so we don't clobber it).
if [ "${SKIP_BUILD:-0}" != "1" ]; then
  hugo --gc --minify
fi

fail=0
assert_file() { if [ ! -f "$1" ]; then echo "MISSING: $1"; fail=1; fi; }
assert_grep() { if ! grep -Eq "$2" "$1" 2>/dev/null; then echo "NO MATCH /$2/ in $1"; fail=1; fi; }

# locale homepages (en at root, zh/th in subdirs)
assert_file public/index.html
assert_file public/zh/index.html
assert_file public/th/index.html

# the sample news post in every locale
assert_file public/news/welcome/index.html
assert_file public/zh/news/welcome/index.html
assert_file public/th/news/welcome/index.html

# correct lang attribute per locale.
# NOTE: `hugo --minify` strips quotes around attribute values (lang="en" -> lang=en),
# so every attribute assertion is quote-tolerant (ERE: "? = optional quote). Verified.
assert_grep public/index.html '<html lang="?en'
assert_grep public/zh/index.html '<html lang="?zh'
assert_grep public/th/index.html '<html lang="?th'

# the language switcher actually links the OTHER locales (deliverable, not just files)
assert_grep public/index.html 'href="?/zh/"?'
assert_grep public/index.html 'href="?/th/"?'

# localized content actually rendered (visible text survives minify)
assert_grep public/index.html 'Masters International School'
assert_grep public/zh/news/welcome/index.html '欢迎'

if [ "$fail" -ne 0 ]; then echo "check-build: FAIL"; exit 1; fi
echo "check-build: OK — build + i18n routes + switcher + content verified"
```

Then: `chmod +x scripts/check-build.sh`

- [ ] **Step 5: Run the test to verify it fails**

Run: `bash scripts/check-build.sh`
Expected: FAIL — `hugo` errors with no config/content, or `MISSING: public/index.html`. (Confirms the test is real before content exists.)

- [ ] **Step 6: Write `hugo.toml`**

```toml
baseURL = "https://www.mastersinternationalschool.org/"
title = "Masters International School"
defaultContentLanguage = "en"
defaultContentLanguageInSubdir = false
enableRobotsTXT = true

[languages]
  # Hugo v0.158+ : use `label` (not languageName) and `locale` (not languageCode);
  # the old keys emit deprecation warnings. Verified clean on v0.162.1.
  [languages.en]
    label = "English"
    locale = "en-US"
    weight = 1
    title = "Masters International School"
  [languages.zh]
    label = "中文"
    locale = "zh-CN"
    weight = 2
    title = "曼谷国际学校"
  [languages.th]
    label = "ไทย"
    locale = "th-TH"
    weight = 3
    title = "โรงเรียนนานาชาติ"

[menus]
  # intentionally empty in Phase 1
```

- [ ] **Step 7: Write `layouts/_default/baseof.html`**

```html
<!DOCTYPE html>
<html lang="{{ .Site.Language.Lang }}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{{ if .IsHome }}{{ .Site.Title }}{{ else }}{{ .Title }} · {{ .Site.Title }}{{ end }}</title>
</head>
<body>
  <header>
    <a href="{{ .Site.Home.RelPermalink }}">{{ .Site.Title }}</a>
    <nav aria-label="languages">
      {{ range .Translations }}<a href="{{ .RelPermalink }}">{{ .Language.Label }}</a>{{ end }}
    </nav>
  </header>
  <main>
    {{ block "main" . }}{{ end }}
  </main>
</body>
</html>
```

Note: `.Site.Language.Lang` yields the language key (`en`/`zh`/`th`) — exactly the `lang` attribute we want — and is NOT deprecated. `.Language.Label` is the v0.158+ replacement for `.LanguageName`. Verified warning-free on v0.162.1.

- [ ] **Step 8: Write `layouts/index.html`**

```html
{{ define "main" }}
  <h1>{{ .Title }}</h1>
  {{ .Content }}
  <section>
    <h2>News</h2>
    <ul>
      {{ range (where .Site.RegularPages "Section" "news") }}
        <li><a href="{{ .RelPermalink }}">{{ .Title }}</a></li>
      {{ end }}
    </ul>
  </section>
{{ end }}
```

- [ ] **Step 9: Write `layouts/_default/list.html`**

```html
{{ define "main" }}
  <h1>{{ .Title }}</h1>
  {{ .Content }}
  <ul>
    {{ range .Pages }}
      <li><a href="{{ .RelPermalink }}">{{ .Title }}</a></li>
    {{ end }}
  </ul>
{{ end }}
```

- [ ] **Step 10: Write `layouts/_default/single.html`**

```html
{{ define "main" }}
  <article>
    <h1>{{ .Title }}</h1>
    {{ with .Date }}<time datetime="{{ .Format "2006-01-02" }}">{{ .Format "2006-01-02" }}</time>{{ end }}
    {{ .Content }}
  </article>
{{ end }}
```

- [ ] **Step 11: Write home content (3 locales)**

`content/_index.en.md`:
```markdown
---
title: "Masters International School"
---
Welcome to Masters International School.
```
`content/_index.zh.md`:
```markdown
---
title: "曼谷国际学校"
---
欢迎来到 Masters International School。
```
`content/_index.th.md`:
```markdown
---
title: "โรงเรียนนานาชาติ"
---
ยินดีต้อนรับสู่ Masters International School
```

- [ ] **Step 12: Write the `news` section index (3 locales)**

`content/news/_index.en.md`:
```markdown
---
title: "News"
---
```
`content/news/_index.zh.md`:
```markdown
---
title: "新闻"
---
```
`content/news/_index.th.md`:
```markdown
---
title: "ข่าวสาร"
---
```

- [ ] **Step 13: Write the sample news post (3 locales)**

`content/news/welcome.en.md`:
```markdown
---
title: "Welcome"
date: 2026-06-19
---
This is the first post. It exists so the CMS and the bot have something to edit.
```
`content/news/welcome.zh.md`:
```markdown
---
title: "欢迎"
date: 2026-06-19
---
这是第一篇文章，留给 CMS 和机器人练手。
```
`content/news/welcome.th.md`:
```markdown
---
title: "ยินดีต้อนรับ"
date: 2026-06-19
---
นี่คือโพสต์แรก มีไว้ให้ CMS และบอททดลองแก้ไข
```

- [ ] **Step 14: Write the `about` singleton page (3 locales)**

`content/about.en.md`:
```markdown
---
title: "About"
---
About Masters International School.
```
`content/about.zh.md`:
```markdown
---
title: "关于我们"
---
关于 Masters International School。
```
`content/about.th.md`:
```markdown
---
title: "เกี่ยวกับเรา"
---
เกี่ยวกับ Masters International School
```

- [ ] **Step 15: Run the test to verify it passes**

Run: `bash scripts/check-build.sh`
Expected: `check-build: OK — build + i18n routes + switcher + content verified`
(This exact skeleton was dry-run on Hugo v0.162.1 and passes with no deprecation warnings.)

- [ ] **Step 16: Commit (skeleton + the already-present CLAUDE.md and design docs)**

```bash
git add -A
git commit -m "feat: multilingual Hugo skeleton (en/zh/th) + build check

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```
Expected: a commit containing `hugo.toml`, `layouts/`, `content/`, `scripts/check-build.sh`, `.gitignore`, `CLAUDE.md`, `docs/superpowers/...`.

---

### Task 2: GitHub Actions workflow (Hugo → Pages)

**Files:**
- Create: `.github/workflows/deploy.yml`

**Interfaces:**
- Consumes: `scripts/check-build.sh` (Task 1) as the CI build+verify step.
- Produces: a workflow that, on push to `main` (and manual dispatch), builds with the Pages `baseURL` and deploys the `public/` artifact to GitHub Pages. Exercised live in Task 3.

- [ ] **Step 1: Write `.github/workflows/deploy.yml`**

`HUGO_VERSION: 0.162.1` matches the verified local version (Task 1, Step 1); update it only if your local `hugo version` differs. Action versions below were verified to resolve (configure-pages@v6, upload-pages-artifact@v5, deploy-pages@v5, actions-hugo@v3).

```yaml
name: Deploy Hugo site to Pages

on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: pages
  cancel-in-progress: false

jobs:
  build:
    runs-on: ubuntu-latest
    env:
      HUGO_VERSION: 0.162.1
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - name: Setup Hugo
        uses: peaceiris/actions-hugo@v3
        with:
          hugo-version: ${{ env.HUGO_VERSION }}
          extended: true
      - name: Setup Pages
        id: pages
        uses: actions/configure-pages@v6
      - name: Build and verify
        run: |
          hugo --gc --minify --baseURL "${{ steps.pages.outputs.base_url }}/"
          SKIP_BUILD=1 bash scripts/check-build.sh
      - name: Upload artifact
        uses: actions/upload-pages-artifact@v5
        with:
          path: ./public

  deploy:
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v5
```

Note: the authoritative build (with the Pages `--baseURL`) runs first; `SKIP_BUILD=1` makes `check-build.sh` verify the existing `public/` instead of rebuilding, so the artifact uploaded keeps the correct baseURL. Locally (Task 1) `check-build.sh` is run without `SKIP_BUILD`, so it builds.

- [ ] **Step 2: Validate the workflow YAML parses**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/deploy.yml')); print('yaml ok')"`
Expected: `yaml ok`

- [ ] **Step 3: Confirm HUGO_VERSION matches local**

Run: `grep HUGO_VERSION .github/workflows/deploy.yml` and compare to `hugo version`.
Expected: the pinned version equals the local extended version from Task 1.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/deploy.yml
git commit -m "ci: build Hugo and deploy to GitHub Pages on push to main

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Create the GitHub repo, push, enable Pages, verify live deploy

**Files:** none (operational — uses `gh`).

**Interfaces:**
- Consumes: the committed repo (Tasks 1–2).
- Produces: a live site at `https://it-of-mis.github.io/website/` serving en/zh/th. This is the Phase 1 deliverable that Phase 2 (Decap) and Phase 3 (bot) build on.

- [ ] **Step 1: Confirm `gh` identity and org access**

Run: `gh auth status` and `gh api orgs/it-of-mis/memberships/dawei101 --jq .role`
Expected: logged in as `dawei101`; role prints `admin` (verified 2026-06-19 — org also has `members_can_create_repositories=true`, so creation will succeed). If this ever returns non-admin/`null`, stop and ask the user to grant rights — do not work around.

- [ ] **Step 2: Create the repo and push `main`**

```bash
gh repo create it-of-mis/website --public --source=. --remote=origin --push
```
Expected: repo created; `main` pushed; `origin` set. Confirm: `git remote -v` shows `it-of-mis/website`.

- [ ] **Step 3: Enable Pages with the GitHub Actions build type**

```bash
gh api -X POST repos/it-of-mis/website/pages -f build_type=workflow
```
Expected: HTTP 201 with a JSON body (or, if it already exists, a 409 — then run the same with `-X PUT` to set `build_type=workflow`). Verify: `gh api repos/it-of-mis/website/pages --jq .build_type` prints `workflow`.

- [ ] **Step 4: Watch the deploy workflow to success**

```bash
gh run list --workflow deploy.yml --limit 1
gh run watch "$(gh run list --workflow deploy.yml --limit 1 --json databaseId --jq '.[0].databaseId')" --exit-status
```
Expected: the run completes with conclusion `success`. If the build job fails on `check-build.sh`, fix the cause in Tasks 1–2 and push again — do not disable the check.

- [ ] **Step 5: Verify the live site across locales**

```bash
base="https://it-of-mis.github.io/website"
for path in "/" "/zh/" "/th/" "/news/welcome/" "/zh/news/welcome/"; do
  code=$(curl -s -o /dev/null -w '%{http_code}' "$base$path")
  echo "$path -> $code"
done
curl -s "$base/zh/news/welcome/" | grep -q '欢迎' && echo "zh content OK"
```
Expected: every path returns `200`; `zh content OK` prints. (Pages may take 1–2 min after the run to serve; re-run if the first hit 404s.)

- [ ] **Step 6: Record the live URL in the repo**

Append the live URL to the top of `CLAUDE.md`'s infra section is optional; at minimum confirm and report it to the user. No commit required for Phase 1 completion.

---

## Self-Review

**Spec coverage (Phase 1 portion of `2026-06-19-mis-website-pipeline-design.md`):**
- §4 Phase 1 "Hugo skeleton + repo + Pages" → Tasks 1–3. ✅
- §3.2 i18n multiple-files / en at root → `hugo.toml` (Step 6) + filename-suffixed content + `check-build.sh` assertions. ✅
- §4 Phase 1 "done when push redeploys; en/zh/th render" → Task 3 Steps 4–5. ✅
- §8 risk "org repo-create permission" → Task 3 Step 1 explicit gate. ✅
- §8 risk "public repo Pages" → Global Constraints (public). ✅
- baseURL/DNS-last (§4 Final) → workflow uses Pages `base_url`; no hardcoded prod domain in build. ✅
- Phases 2 (Decap + Zitadel auth proxy) and 3 (bot repoint + WhatsApp + ops removal) are intentionally NOT in this plan — see "Subsequent plans" below.

**Placeholder scan:** No TBD/TODO. `HUGO_VERSION: 0.162.1` is the verified local version (not a placeholder); Task 2 Step 3 enforces the match. The entire Task 1 skeleton (config + layouts + content + `check-build.sh`) was dry-run on Hugo v0.162.1 and passes warning-free with `--minify`; action versions and the org-admin permission were verified live on 2026-06-19.

**Type/name consistency:** `scripts/check-build.sh` is defined in Task 1 and referenced by exact path in Task 2 (CI) and Task 3. Content slugs (`news/welcome`, locale codes `zh-CN`→`lang="zh"`) are consistent between layouts, content, and the grep assertions.

---

## Subsequent plans (not yet written)

These get their own plan documents, written after Phase 1 deploys, because each depends on Phase 1's concrete output or has an open risk to verify first:

- **Phase 2 — Decap CMS + Zitadel auth proxy.** Add `/admin` (Decap `config.yml`: i18n `multiple_files` over the content model created in Phase 1, `editorial_workflow`), and add an OIDC+PKCE OAuth endpoint to the existing Go orchestrator that gates on `cms-*` roles and returns the bot fine-grained PAT to Decap. Needs Phase 1's real content structure and the manually-minted PAT.
- **Phase 3 — Repoint `website` bot + WhatsApp + author binding; remove `ops` bot.** Swap the bot's MCP from `mis-cms` to a GitHub MCP on `it-of-mis/website`; add the WhatsApp channel + phone→person identity map + commit attribution; keep "drafts only" (PRs). **Blocking pre-check:** verify nanobot v0.2.1 has a native WhatsApp channel; if not, scope a thin WhatsApp Cloud API ↔ websocket bridge. Also removes `bots/ops/`, its systemd unit, env vars, and `deploy.sh` loop entry.
