---
name: hugo
description: |
  Comprehensive Hugo static-site-generator knowledge, ADAPTED for the Masters
  International School (MIS) website: a multilingual (en/zh/th) Hugo site whose Git
  repo is the single source of truth, edited by humans via Decap CMS and by AI via
  MCP, built by GitHub Actions and deployed to GitHub Pages.

  Use this skill when: scaffolding or modifying Hugo content and layouts, configuring
  hugo.toml (this repo uses TOML config), working with Hugo's i18n / multilingual
  setup (multiple-files, language-by-filename-suffix), editing the GitHub Actions
  build/deploy pipeline, wiring Decap CMS collections, choosing Hugo Extended vs
  Standard, troubleshooting baseURL/asset 404s, fixing frontmatter format issues,
  preventing date-related build failures, or resolving Hugo build warnings that the
  CI gate (`--panicOnWarning`) turns into hard failures.

  Keywords: hugo, hugo-extended, static-site-generator, ssg, go-templates, goldmark,
  markdown, multilingual, i18n, multiple-files, language-suffix, decap-cms, git-gateway,
  zitadel, oauth-proxy, github-pages, github-actions, peaceiris, panic-on-warning,
  baseurl-error, frontmatter, toml-config, yaml-frontmatter, hugo-themes, hugo-modules,
  shortcodes, image-processing, taxonomies, hugo-pipes, tailwind, version-mismatch.
license: MIT
metadata:
  version: "2.0.0-mis"
  upstream: "github.com/jackspace/claudeskillz/skills/hugo (MIT)"
  adapted_for: "it-of-mis/website — GitHub Pages + Decap + i18n(en/zh/th)"
  hugo_version: "0.162.1"
  stack: "GitHub Pages via Actions (peaceiris/actions-hugo); Decap CMS; Zitadel SSO"
  notes: "Cloudflare-Workers and Sveltia/Tina chapters from upstream were replaced with this repo's real stack."
---

# Hugo Static Site Generator (MIS adaptation)

**Status**: Adapted for this repo. The Hugo fundamentals and the 9 known-issue
preventions are upstream; the **deployment** (GitHub Pages, not Cloudflare) and
**CMS** (Decap, not Sveltia/Tina) chapters are rewritten to match this project.

> Attribution: derived from the MIT-licensed `hugo` skill in
> `jackspace/claudeskillz`. Deployment/CMS/i18n sections were replaced to fit the MIS
> site's actual architecture. See `CLAUDE.md` and `docs/superpowers/specs/` for the
> authoritative project design — this skill defers to those on anything project-specific.

**This repo at a glance** (verify against the live files, they win):
- Config: **`hugo.toml`** (TOML), `baseURL = "https://www.mastersinternationalschool.org/"`.
- Languages: **`en` (default)**, `zh`, `th`; `defaultContentLanguageInSubdir = false`.
  Uses Hugo v0.158+ keys `label` + `locale` (NOT the deprecated `languageName`/`languageCode`).
- i18n layout: flat `content/`, language by filename suffix:
  `content/<section>/<slug>.en.md`, `.zh.md`, `.th.md` (Decap `structure: multiple_files`).
- Build/deploy: `.github/workflows/deploy.yml` — `peaceiris/actions-hugo` (extended),
  `hugo --gc --minify --panicOnWarning`, then `scripts/check-build.sh`, then GitHub Pages.
- **Warning-gated build**: any Hugo WARNING fails CI. Deprecation warnings = broken build.

---

## Quick Start

### 1. Install Hugo Extended

**CRITICAL**: Always install Hugo **Extended** edition (not Standard) unless you're
certain you don't need SCSS/Sass support. Most themes require Extended, and the CI uses
Extended (`extended: true`).

```bash
# macOS
brew install hugo

# Verify Extended edition AND match the CI version (0.162.1) closely
hugo version   # Should show "+extended"
```

**Why it matters**: Extended includes SCSS/Sass processing; Standard fails with
"SCSS support not enabled". Extended has no downsides.

### 2. Run this repo locally

```bash
# From the repo root
hugo server                 # live reload at http://localhost:1313
hugo server --buildDrafts   # include drafts

# Reproduce the CI build EXACTLY before pushing (this is what the gate runs):
hugo --gc --minify --panicOnWarning
bash scripts/check-build.sh
```

If `hugo --panicOnWarning` errors locally, it will fail CI too — fix it before pushing.

---

## The Setup Process (mapped to this repo)

### Step 1: Installation and Verification

```bash
hugo version   # must show v0.16x.x+extended; keep close to CI's 0.162.1
```
Pin the version in CI (already done: `HUGO_VERSION: 0.162.1` in `deploy.yml`). Local vs
CI version drift is a top cause of "works locally, fails in CI".

### Step 2: Project structure

```
website/
├── hugo.toml             # site config (TOML) — languages, baseURL, menus
├── archetypes/           # content templates
├── content/              # flat; language by filename suffix (.en/.zh/.th.md)
├── data/                 # data files (YAML/JSON/TOML)
├── layouts/              # templates & partials (language switcher lives here)
├── static/               # static assets, incl. /admin for Decap CMS
├── scripts/check-build.sh# build-time assertions (run in CI)
├── .github/workflows/    # deploy.yml (build + Pages)
└── public/               # build output — git-ignored, never commit
```

### Step 3: Themes (note for this repo)

This site is intentionally minimal (Phase 1 skeleton) and does **not** rely on a heavy
theme. If a theme is added later, prefer **Hugo Modules** or a Git submodule with
`--depth=1`, set `theme:` in `hugo.toml`, and add `submodules: recursive` to the
checkout step in `deploy.yml` so CI fetches it.

### Step 4: Configuration (`hugo.toml`)

This repo uses TOML. The multilingual block is the important part — keep using the
modern keys so the warning gate stays green:

```toml
baseURL = "https://www.mastersinternationalschool.org/"
title = "Masters International School"
defaultContentLanguage = "en"
defaultContentLanguageInSubdir = false
enableRobotsTXT = true

[languages]
  # Hugo v0.158+: use `label` (NOT languageName) and `locale` (NOT languageCode).
  # The old keys emit deprecation warnings → `--panicOnWarning` fails the build.
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
  # empty in Phase 1
```

**Config format note**: Upstream pushes YAML "for CMS compatibility" — that was
Sveltia-specific. **Decap CMS reads its own `static/admin/config.yml` regardless of
Hugo's config format**, so `hugo.toml` is fine here. Don't migrate the config to YAML
just for the CMS.

### Step 5: Content & i18n (the MIS pattern)

Content is **flat** and language is encoded in the **filename suffix** — this matches
Decap's `structure: multiple_files`:

```
content/
├── about/
│   ├── index.en.md
│   ├── index.zh.md
│   └── index.th.md
└── _index.en.md   _index.zh.md   _index.th.md
```

Frontmatter (YAML, `---` delimiters — recommended for Decap):

```yaml
---
title: "About Us"
date: 2026-01-01
draft: false
---

Body content here.
```

**Key points**
- `draft: false` is required for a page to appear in production.
- A future `date` hides the page in production unless built with `--buildFuture`.
- Keep the same `<slug>` across the three language files so Hugo links translations.
- `defaultContentLanguageInSubdir = false` → English serves at `/`, others under `/zh/`, `/th/`.

### Step 6: Build and Development

```bash
hugo server                              # dev, live reload, port 1313
hugo --gc --minify --panicOnWarning      # CI-equivalent production build
```
Production output lands in `public/` (git-ignored). Build is sub-second for this site.

### Step 7: Deployment — GitHub Pages via GitHub Actions

This repo deploys to **GitHub Pages**, built by Actions on push to `main`. The pipeline
lives in `.github/workflows/deploy.yml` and looks like this:

```yaml
name: Deploy Hugo site to Pages
on:
  push: { branches: [main] }
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency: { group: pages, cancel-in-progress: false }

jobs:
  build:
    runs-on: ubuntu-latest
    env: { HUGO_VERSION: 0.162.1 }
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }          # full history (for .GitInfo/.Lastmod)
      - uses: peaceiris/actions-hugo@v3
        with: { hugo-version: "${{ env.HUGO_VERSION }}", extended: true }
      - id: pages
        uses: actions/configure-pages@v6
      - name: Build and verify
        run: |
          hugo --gc --minify --panicOnWarning --baseURL "${{ steps.pages.outputs.base_url }}/"
          SKIP_BUILD=1 bash scripts/check-build.sh
      - uses: actions/upload-pages-artifact@v5
        with: { path: ./public }
  deploy:
    needs: build
    runs-on: ubuntu-latest
    environment: { name: github-pages, url: "${{ steps.deployment.outputs.page_url }}" }
    steps:
      - id: deployment
        uses: actions/deploy-pages@v5
```

**Key points for this pipeline**
- **baseURL is injected at build time** from `steps.pages.outputs.base_url` — do not
  hardcode the Pages URL in commands. (The `hugo.toml` baseURL is the canonical custom
  domain; CI overrides it for the Pages artifact.) Asset 404s almost always trace back
  to a baseURL mismatch.
- `--panicOnWarning` is the quality gate. **Any** Hugo warning (deprecated config keys,
  missing translations, raw-HTML in Markdown, etc.) fails the build. Treat warnings as errors.
- `scripts/check-build.sh` runs static assertions on `public/` (e.g. that language pages
  built and the language-switcher hrefs are correct). Keep assertions baseURL-agnostic.
- If you add a theme as a submodule, add `submodules: recursive` to the checkout step.

---

## Critical Rules

### Always Do
✅ Install Hugo **Extended**; keep local version near CI's `0.162.1`.
✅ Reproduce CI locally with `hugo --gc --minify --panicOnWarning` before pushing.
✅ Use the modern i18n keys (`label`, `locale`) — deprecation warnings fail CI.
✅ Keep matching `<slug>` across `.en/.zh/.th` files so translations link.
✅ Let CI inject `--baseURL` for Pages; keep `check-build.sh` assertions baseURL-agnostic.
✅ `draft: false` for anything that must publish.
✅ Keep `public/` and `resources/_gen/` git-ignored.

### Never Do
❌ Don't hardcode the GitHub Pages URL into build commands or assertions.
❌ Don't reintroduce deprecated keys (`languageName`, `languageCode`) — they warn → fail.
❌ Don't commit `public/`.
❌ Don't migrate `hugo.toml` to YAML "for the CMS" — Decap doesn't require it.
❌ Don't let local/CI Hugo versions drift far apart.
❌ Don't use future dates carelessly (pages won't publish until the date passes).

---

## Known Issues Prevention (9 upstream + 1 repo-specific)

### Issue #1: SCSS support not enabled
Install Hugo **Extended**. Verify `hugo version | grep extended`. CI uses `extended: true`.

### Issue #2: baseURL errors → broken CSS/JS/image links, asset 404s
Here, CI injects `--baseURL "${{ steps.pages.outputs.base_url }}/"`. Don't hardcode it.
Locally, test with `hugo --baseURL http://localhost:1313/` if you need to mimic a subpath.

### Issue #3: Config/frontmatter format confusion
This repo: **TOML config** (`hugo.toml`), **YAML content frontmatter** (`---`). Don't mix
delimiters within a file. Decap's own config is `static/admin/config.yml` (YAML).

### Issue #4: Local vs CI version mismatch
Pinned via `HUGO_VERSION: 0.162.1`. Keep your local Hugo close to it.

### Issue #5: Frontmatter parse errors
YAML uses `---`; TOML uses `+++`. Invalid YAML fails the build. Validate before commit.

### Issue #6: Theme not found
Only relevant if a theme is added: set `theme:` in config, install via submodule/module,
add `submodules: recursive` to CI checkout, run `git submodule update --init --recursive`.

### Issue #7: Date "time warp" — page visible locally, missing in production
Future-dated page built locally with `--buildFuture` but skipped in prod. Use past/now dates.

### Issue #8: public/ folder conflicts
Keep `public/` git-ignored; rebuild every deploy; never commit generated output.

### Issue #9: Module cache issues
If using Hugo Modules: `hugo mod clean` / `hugo mod tidy`, or prefer submodules.

### Issue #10 (repo-specific): `--panicOnWarning` turns warnings into hard failures
The build runs `--panicOnWarning`. Common triggers in this multilingual repo:
- Deprecated config keys (`languageName`/`languageCode`) → use `label`/`locale`.
- Missing translation strings or i18n lookups with no entry.
- Raw HTML in Markdown when Goldmark `unsafe` is off.
Fix the warning at the source; never strip `--panicOnWarning` to "make it pass".

---

## Decap CMS Integration (replaces upstream's Sveltia/Tina chapters)

This project uses **Decap CMS** (the maintained fork of Netlify CMS), a static SPA at
`/admin`. Both the human track (Decap) and the AI track (nanobot + GitHub MCP) commit to
the **same Git repo via the GitHub API using one shared bot credential**; a **Zitadel SSO**
session gates entry and the operating user's identity is stamped into each commit. See
`CLAUDE.md` for the full identity model — this skill only covers the Hugo-facing wiring.

**Admin shell** — `static/admin/index.html`:
```html
<!doctype html>
<html lang="en"><head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title>Content Manager</title>
</head><body>
  <!-- Pin an EXACT version and add Subresource Integrity. A floating range like
       @^3 cannot be SRI-protected (the bytes change), and an unpinned CDN script
       lets a CDN compromise inject arbitrary code into your /admin. Get the hash
       from the release or: curl -s <url> | openssl dgst -sha384 -binary | openssl base64 -A -->
  <script
    src="https://unpkg.com/decap-cms@3.x.y/dist/decap-cms.js"
    integrity="sha384-REPLACE_WITH_REAL_HASH"
    crossorigin="anonymous"></script>
</body></html>
```
> Security: never ship the `/admin` shell with a floating `@^3` and no `integrity`.
> Pin the exact Decap version, compute its SHA-384, and add `crossorigin="anonymous"`.
> Better still, vendor the script locally under `static/admin/` so it ships from your
> own origin and is covered by the same review/CI as the rest of the repo.

**CMS config** — `static/admin/config.yml`. The i18n block must mirror the Hugo layout
(multiple-files, languages `en/zh/th`, default `en`):
```yaml
backend:
  name: git-gateway          # fronted by the project's OAuth proxy → shared GitHub bot
  branch: main

# Multilingual: one file per locale, suffix-named (matches content/<slug>.<lang>.md)
i18n:
  structure: multiple_files
  locales: [en, zh, th]
  default_locale: en

media_folder: "static/images/uploads"
public_folder: "/images/uploads"

collections:
  - name: "pages"
    label: "Pages"
    folder: "content"
    create: true
    i18n: true
    slug: "{{slug}}"
    fields:
      - { label: "Title", name: "title", widget: "string", i18n: true }
      - { label: "Date",  name: "date",  widget: "datetime" }
      - { label: "Draft", name: "draft", widget: "boolean", default: false }
      - { label: "Body",  name: "body",  widget: "markdown", i18n: true }
```

**Key points**
- `i18n.structure: multiple_files` + suffix filenames is exactly Hugo's layout here — do
  not switch to folder-per-language without also changing `content/` and `hugo.toml`.
- Auth/OAuth is handled by the project's proxy + Zitadel, NOT Netlify Identity. Don't add
  Netlify Identity widgets.
- `local_backend: true` can be added temporarily for offline CMS testing (`npx decap-server`),
  but never commit it enabled.

---

## Tailwind CSS v4 (optional — only if/when custom styling is added)

Hugo integrates Tailwind v4 via Hugo Pipes + PostCSS (NOT the Vite plugin). If this site
later needs utility CSS:
1. `npm install -D tailwindcss postcss autoprefixer`
2. In `hugo.toml`, enable `[build] writeStats = true` (generates `hugo_stats.json` for purging).
3. Point `tailwind.config.js` `content` at `./hugo_stats.json`, `./layouts/**/*.html`, `./content/**/*.{html,md}`.
4. Process in the base template:
   ```html
   {{ $style := resources.Get "css/main.css" | resources.PostCSS }}
   {{ if hugo.IsProduction }}{{ $style = $style | minify | fingerprint }}{{ end }}
   <link rel="stylesheet" href="{{ $style.RelPermalink }}">
   ```
Do not reuse `tailwind-v4-shadcn` (Vite/React) patterns — incompatible with Hugo's pipeline.

---

## Advanced Topics (unchanged from upstream — universally useful)

### Custom Shortcodes
```go-html-template
<!-- layouts/shortcodes/youtube.html -->
<div class="youtube-embed">
  <iframe src="https://www.youtube.com/embed/{{ .Get 0 }}" allowfullscreen></iframe>
</div>
```
Usage: `{{< youtube dQw4w9WgXcQ >}}`

### Image Processing
```go-html-template
{{ $image := resources.Get "images/photo.jpg" }}
{{ $resized := $image.Resize "800x" }}
<img src="{{ $resized.RelPermalink }}" alt="Photo">
```

### Taxonomies & Data Files
```toml
# hugo.toml
[taxonomies]
  tag = "tags"
  category = "categories"
```
```go-html-template
{{ range .Site.Data.team }}<div>{{ .name }} — {{ .role }}</div>{{ end }}
```

---

## Note on bundled resources

The upstream skill referenced `scripts/`, `templates/`, `references/`, and `assets/`
directories — **those are not shipped** in the source repo, so ignore those pointers.
This repo's real automation is `scripts/check-build.sh` (build assertions, run in CI).

---

## Official Documentation
- Hugo: https://gohugo.io/documentation/
- Hugo multilingual: https://gohugo.io/content-management/multilingual/
- Decap CMS: https://decapcms.org/docs/
- GitHub Pages + Actions: https://github.com/actions/deploy-pages
- peaceiris/actions-hugo: https://github.com/peaceiris/actions-hugo

## Setup Checklist (this repo)
- [ ] Hugo **Extended** installed, version near CI's `0.162.1` (`hugo version` shows `+extended`).
- [ ] `hugo --gc --minify --panicOnWarning` passes locally (no warnings).
- [ ] `bash scripts/check-build.sh` passes locally.
- [ ] i18n config uses `label`/`locale`; content files use matching `<slug>.en/.zh/.th.md`.
- [ ] No hardcoded Pages URL in build commands or assertions.
- [ ] `public/` and `resources/_gen/` git-ignored; nothing generated committed.
- [ ] Decap `config.yml` i18n block matches the Hugo multiple-files layout.
