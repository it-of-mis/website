# MIS Website Phase 2 — Decap CMS + Zitadel OAuth Bridge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement **Tasks 1–5** (code) task-by-task. **Tasks 6–9 are a manual Deployment & Integration Runbook** executed by the human operator (they touch live infra, secrets, and a browser) — do NOT dispatch a subagent for them. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the human content-editing loop: Decap CMS at `/admin` lets a Zitadel-SSO'd `cms-*` editor edit Hugo content, which lands as a GitHub PR and (on publish/merge) redeploys the site — with no editor needing a GitHub account.

**Architecture:** Decap's static admin (`/admin/index.html` + `config.yml`) uses the GitHub backend with `editorial_workflow`, pointed at a self-hosted OAuth provider (`base_url`). That provider is **two new endpoints on the existing Go orchestrator** (`/cms/auth`, `/cms/callback`) which reuse the orchestrator's vetted Zitadel OIDC+PKCE module, gate on `cms-*` roles, and hand Decap a **single shared fine-grained GitHub PAT** via the Decap `window.postMessage` handshake. Content is restructured into Hugo **folder collections** (the only collection type Decap supports for per-locale separate files).

**Tech Stack:** Hugo 0.162.1 (extended); Decap CMS 3.14.1 (CDN); Go 1.25 orchestrator (chi, coreos/go-oidc/v3, x/oauth2, gorilla/securecookie); Zitadel OIDC; GitHub Pages + Actions.

## Global Constraints

Every task's requirements implicitly include these (copied verbatim from the spec / CLAUDE.md / verified recon):

- **Two repos.** Website code lives in **`it-of-mis/website`** (working dir `/Users/david/projects/it-of-mis/website`, remote `git@github.com:it-of-mis/website.git`). Orchestrator code lives in the **sibling repo** at `/Users/david/projects/outsources/mastersinternational.org`, Go module root `bots/orchestrator/` (module path `mis/bots-orchestrator`). Each task states its repo; commit in that repo.
- **Languages:** `en` (primary, at site root), `zh`, `th`. `defaultContentLanguageInSubdir = false` (en at root, zh/th under `/zh/`, `/th/`). `zh-Hant` reserved, NOT enabled.
- **Hugo i18n layout:** translation-by-filename, `content/<section>/<slug>.<lang>.md`.
- **Build is warning-gated:** CI runs `hugo --gc --minify --panicOnWarning`. No new Hugo warnings.
- **`hugo --minify` strips quotes** from HTML attribute values (`lang="en"` → `lang=en`). HTML assertions must be quote-tolerant. Static files (`static/admin/*`) are copied verbatim and are NOT minified.
- **Never copy secrets into either repo.** No PAT, client secret, or session secret in any committed file. Secrets live only in the box's gitignored `/home/ubuntu/bots/.env`. Committed `*.example` files name env KEYS only.
- **No individual GitHub tokens for users.** One shared machine credential (fine-grained PAT v1, scoped to `it-of-mis/website`) is the only GitHub write credential; identity/authorization is enforced at the Zitadel SSO layer, attribution is via commit author/message.
- **Zitadel (verified):** issuer `https://auth.mastersinternationalschool.org`; org `mis` (`375822041443532802`); project **"MIS Website" `375950440665186306`**; `projectRoleAssertion = true`. CMS roles (exact keys): `cms-superadmin`, `cms-editor`, `cms-admissions`, `cms-hr`. Roles arrive in the id_token under claim `urn:zitadel:iam:org:project:roles` when scope `urn:zitadel:iam:org:project:roles` is requested. Apps are created via the management API (`POST /management/v1/projects/{id}/apps/oidc`) using the automation PAT in `zitadel/.pat`.
- **Orchestrator host (verified):** Lightsail `mis-ops-bot`, public IP `18.141.228.49`, **SSH on port 1022**, key `~/.ssh/nanobot-ops.pem`. Caddy terminates TLS for **`bots.mastersinternationalschool.org`** and reverse-proxies to the orchestrator on `127.0.0.1:8088`. The orchestrator already owns `/auth/login`, `/auth/callback`, `/auth/logout`, and a `/*` catch-all proxy — the CMS flow MUST use the distinct `/cms/*` paths.
- **AWS constitution:** any `aws` CLI call uses `--profile mis` and an explicit `--region` (resources in `ap-southeast-1`).

---

## Why these shapes (verified design decisions)

These were verified against source/docs during planning; do not re-litigate them:

1. **Decap returns an opaque GitHub bearer token.** Decap's GitHub backend puts the token straight into `Authorization: token <X>` against `api.github.com`; it does no OAuth-app verification, scope check, or refresh. So the OAuth provider may return a **pre-existing fine-grained PAT** instead of minting a per-user OAuth token. (Confirmed in `decap-cms-backend-github/src/API.ts` `requestHeaders()` and `decap-cms-lib-auth/src/netlify-auth.js`.)
2. **A fine-grained PAT with {Contents: R/W, Pull requests: R/W, Metadata: R}** covers every endpoint Decap's GitHub backend + `editorial_workflow` uses (Git Database blobs/trees/commits/refs, pulls, PR-merge, and PR labels via the issues-labels endpoint — Issues permission NOT required for PR labels). Deploy-preview status links would additionally need `Commit statuses: R`, which we omit (GitHub Pages has no Decap deploy previews).
3. **Decap `multiple_files` i18n (per-locale separate files, matching Hugo) works ONLY for folder collections, not file collections.** So singleton pages become a `content/pages/` **folder** collection; the homepage `_index` is deferred (special Hugo construct).
4. **Folder collections enumerate every `.md` at depth 1, including Hugo section-index `_index.*` files; there is no native exclude.** We keep the localized `content/news/_index.<lang>.md` and exclude it from the CMS using the documented **marker-field + `filter`** pattern (`type: post` on posts, `filter: {field: type, value: post}`). `content/pages/` has no `_index`, so it needs no filter.
5. **One entry = one PR across all locales.** A draft of entry `<slug>` in collection `<c>` produces ONE branch `cms/<c>/<slug>` and ONE PR containing all locale files — fits the SSO-attribution commit model.
6. **Decap's default `config.yml` fetch is relative to `index.html`** (`getConfigUrl()` returns the bare token `'config.yml'`), so the admin works unchanged at both `/website/admin/` (Pages subpath) and `/admin/` (custom domain). We additionally add an explicit **relative** `<link rel="cms-config-url" href="config.yml" type="text/yaml">` for clarity. Never use an absolute config href.
7. **Reuse, don't fork.** The orchestrator already implements Zitadel OIDC+PKCE (`internal/oidcauth`), role parsing (`internal/identity`), and is fronted by Caddy on `bots.host`. The CMS bridge is a thin new package reusing that module — adding only a configurable txn-cookie `Path` so the `/cms` flow's cookie doesn't collide with the `/auth` member-proxy flow.

---

## File Structure

### Repo A — `it-of-mis/website` (`/Users/david/projects/it-of-mis/website`)

- Move: `content/about.{en,zh,th}.md` → `content/pages/about.{en,zh,th}.md` — About becomes a CMS-editable `pages` folder-collection entry.
- Modify: `content/news/welcome.{en,zh,th}.md` — add `type: post` frontmatter marker (so the `news` collection's `filter` excludes the section index).
- Create: `static/admin/index.html` — Decap admin loader (pinned CDN bundle + relative config link). Hugo copies `static/` verbatim to `public/admin/`.
- Create: `static/admin/config.yml` — Decap configuration (GitHub backend via the orchestrator OAuth bridge, i18n, editorial_workflow, two folder collections).
- Modify: `scripts/check-build.sh` — update About path assertions to `pages/about`; add admin-file + admin-config assertions.

### Repo B — orchestrator (`/Users/david/projects/outsources/mastersinternational.org/bots/orchestrator`)

- Modify: `internal/oidcauth/auth.go` — add a configurable `CookiePath` field to `Authenticator` (defaults to `/auth`), used by `LoginHandler`.
- Modify: `internal/oidcauth/auth_test.go` — tests for default vs custom cookie path.
- Create: `internal/cmsauth/cmsauth.go` — the Decap OAuth bridge: `AuthStart` (begin Zitadel flow) and `Callback` (verify, role-gate, postMessage the bot PAT).
- Create: `internal/cmsauth/cmsauth_test.go` — behavior tests (authorized → token; forbidden → error; bad state → error).
- Modify: `internal/config/config.go` — add an optional `cms:` config section (`CMSConfig`) + `CMSEnabled()`; resolve its secrets only when present.
- Modify: `internal/config/config_test.go` — tests for CMS secret resolution and the disabled-when-absent path.
- Modify: `cmd/orchestrator/main.go` — build the CMS `Authenticator` + `cmsauth.Handler` when `CMSEnabled()`, wire into `server.Deps`.
- Modify: `internal/server/server.go` — add a `cms *cmsauth.Handler` dependency and register `/cms/auth` + `/cms/callback` before the `/*` catch-all.
- Modify: `internal/server/server_test.go` — test that `/cms/auth` routes to the bridge (302 to the IdP), not the member proxy.
- Modify: `bots/orchestrator/bots.yaml.example` — add a commented `cms:` example section.
- Modify: `bots/.env.example` — add `CMS_OIDC_SECRET`, `WEBSITE_CMS_GITHUB_PAT`, and the currently-missing `BOTS_OIDC_SECRET` / `BOTS_SESSION_SECRET` keys.

### Test strategy (no `local_backend`)

Per the chosen approach, there is no Decap local proxy. Code tasks are verified deterministically: **Repo A** via `hugo --gc --minify` + `scripts/check-build.sh`; **Repo B** via `go test ./...`. The live editorial loop (login → draft → PR → publish → redeploy) is verified once, end-to-end, against the real GitHub repo in **Task 9**.

---

## Task 1 — Restructure content into CMS-compatible folder collections (Repo A)

**Repo:** `it-of-mis/website`

**Files:**
- Move: `content/about.en.md` → `content/pages/about.en.md` (and `.zh.md`, `.th.md`)
- Modify: `content/news/welcome.en.md`, `content/news/welcome.zh.md`, `content/news/welcome.th.md`
- Modify: `scripts/check-build.sh`
- Test: `scripts/check-build.sh` (the build/i18n test itself)

**Interfaces:**
- Produces: the on-disk layout the Decap collections in Task 2 bind to — posts at `content/news/<slug>.<lang>.md` carrying `type: post`; pages at `content/pages/<slug>.<lang>.md`. About now renders at `/pages/about/` (was `/about/`); the localized news section index `content/news/_index.<lang>.md` is unchanged and stays out of the CMS.

- [ ] **Step 1: Update the failing test first (RED) — point About assertions at the new path and add no admin asserts yet**

Edit `scripts/check-build.sh`. Replace the About block (currently lines ~27-29):

```bash
# the about singleton in every locale
assert_file public/about/index.html
assert_file public/zh/about/index.html
assert_file public/th/about/index.html
```

with:

```bash
# the about page (now a content/pages/ folder-collection entry for Decap editing) in every locale
assert_file public/pages/about/index.html
assert_file public/zh/pages/about/index.html
assert_file public/th/pages/about/index.html
```

- [ ] **Step 2: Run the test to confirm it fails against the OLD layout**

Run: `bash scripts/check-build.sh`
Expected: FAIL — `MISSING: public/pages/about/index.html` (About is still at `content/about.*.md` → renders at `/about/`, not `/pages/about/`).

- [ ] **Step 3: Move About into the `pages` folder**

```bash
mkdir -p content/pages
git mv content/about.en.md content/pages/about.en.md
git mv content/about.zh.md content/pages/about.zh.md
git mv content/about.th.md content/pages/about.th.md
```

Content of the moved files is unchanged. For reference, `content/pages/about.en.md` is:

```markdown
---
title: "About"
---
About Masters International School.
```

(`.zh.md` title `"关于我们"`, body `关于 Masters International School。`; `.th.md` as-is.)

- [ ] **Step 4: Add the `type: post` marker to the news posts**

This marker lets the Decap `news` collection's `filter` exclude the section index. Edit each `content/news/welcome.<lang>.md` to add `type: post` to the frontmatter. `content/news/welcome.en.md` becomes exactly:

```markdown
---
title: "Welcome"
date: 2026-06-19
type: post
---
This is the first post. It exists so the CMS and the bot have something to edit.
```

`content/news/welcome.zh.md` becomes exactly:

```markdown
---
title: "欢迎"
date: 2026-06-19
type: post
---
这是第一篇文章，留给 CMS 和机器人练手。
```

Apply the same single-line `type: post` addition to `content/news/welcome.th.md` (keep its existing title/date/body).

> Why `type: post` is safe in Hugo: it changes the layout-lookup order to `layouts/post/single.html` first, which does not exist, so Hugo falls back to `layouts/_default/single.html` (no warning under `--panicOnWarning`). It does not change the URL or section membership.

- [ ] **Step 5: Run the test to confirm it passes (GREEN)**

Run: `bash scripts/check-build.sh`
Expected: `check-build: OK — build + i18n routes + switcher + content verified`. (The build now renders `/pages/about/`, `/zh/pages/about/`, `/th/pages/about/`; the news posts still render at `/news/welcome/` etc.)

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "content: restructure About into content/pages/ folder + mark news posts (Phase 2 CMS prep)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2 — Ship the Decap CMS admin (Repo A)

**Repo:** `it-of-mis/website`

**Files:**
- Create: `static/admin/index.html`
- Create: `static/admin/config.yml`
- Modify: `scripts/check-build.sh`
- Test: `scripts/check-build.sh`

**Interfaces:**
- Consumes: the content layout from Task 1 (`content/news` posts with `type: post`; `content/pages` entries).
- Produces: `public/admin/index.html` + `public/admin/config.yml`. The config binds Decap to `repo: it-of-mis/website`, `branch: main`, the orchestrator OAuth bridge (`base_url: https://bots.mastersinternationalschool.org`, `auth_endpoint: cms/auth`), `editorial_workflow`, i18n `multiple_files [en, zh, th]`, and the `news` + `pages` folder collections. The `base_url`/`auth_endpoint` pair is the contract the orchestrator endpoints in Tasks 4–5 must satisfy.

- [ ] **Step 1: Add the failing admin assertions to the test (RED)**

Edit `scripts/check-build.sh`. Immediately after the About assertions block, add:

```bash
# Decap CMS admin shipped as static files (Hugo copies static/ verbatim, no minify)
assert_file public/admin/index.html
assert_file public/admin/config.yml
# admin config binds to the right repo + OAuth bridge (static file: exact text, no minify)
assert_grep public/admin/config.yml 'repo: it-of-mis/website'
assert_grep public/admin/config.yml 'base_url: https://bots\.mastersinternationalschool\.org'
assert_grep public/admin/config.yml 'auth_endpoint: cms/auth'
assert_grep public/admin/config.yml 'publish_mode: editorial_workflow'
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `bash scripts/check-build.sh`
Expected: FAIL — `MISSING: public/admin/index.html`.

- [ ] **Step 3: Create the admin loader**

Create `static/admin/index.html` exactly:

```html
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <meta name="robots" content="noindex" />
    <title>MIS Content Manager</title>
    <!-- Explicit + relative: resolves against this file at /admin/ AND /website/admin/ -->
    <link href="config.yml" type="text/yaml" rel="cms-config-url" />
  </head>
  <body>
    <!-- Exact-pinned bundle (no caret) + Subresource Integrity, so a compromised
         CDN cannot serve altered JS. The sha384 hash is computed in Step 3a. -->
    <script
      src="https://unpkg.com/decap-cms@3.14.1/dist/decap-cms.js"
      integrity="sha384-REPLACE_WITH_COMPUTED_HASH"
      crossorigin="anonymous"></script>
  </body>
</html>
```

- [ ] **Step 3a: Compute and insert the SRI hash**

Run:

```bash
curl -fsSL https://unpkg.com/decap-cms@3.14.1/dist/decap-cms.js \
  | openssl dgst -sha384 -binary | openssl base64 -A
```

Take the printed base64 string `<HASH>` and replace `REPLACE_WITH_COMPUTED_HASH` in `static/admin/index.html` so the attribute reads `integrity="sha384-<HASH>"`. (unpkg follows the exact `@3.14.1` pin, so the bundle — and thus the hash — is stable. If a future bump changes the version, recompute.)

Verify the placeholder is gone:

Run: `grep -q 'sha384-REPLACE_WITH_COMPUTED_HASH' static/admin/index.html && echo "STILL PLACEHOLDER (fix)" || echo "SRI hash inserted"`
Expected: `SRI hash inserted`.

- [ ] **Step 4: Create the Decap config**

Create `static/admin/config.yml` exactly:

```yaml
backend:
  name: github
  repo: it-of-mis/website
  branch: main
  base_url: https://bots.mastersinternationalschool.org
  auth_endpoint: cms/auth
  cms_label_prefix: decap-cms/

publish_mode: editorial_workflow

# Subpath today (GitHub Pages); custom domain at DNS cutover. Affects only
# the "go to site" / preview links, never editing.
site_url: https://it-of-mis.github.io/website
display_url: https://it-of-mis.github.io/website

# Media uploads are not a v1 focus. public_folder is root-relative (no /website/
# prefix); Hugo resolves the prefix at render time. Revisit at DNS cutover.
media_folder: static/uploads
public_folder: /uploads

# ASCII kebab-case filenames. Note: zh/th titles sanitize to empty under ascii —
# editors set an explicit Latin slug for non-English-titled entries.
slug:
  encoding: ascii
  clean_accents: true

# No JS preview templates are registered for this Hugo site; disable the pane.
editor:
  preview: false

i18n:
  structure: multiple_files
  locales: [en, zh, th]
  default_locale: en

collections:
  - name: news
    label: News
    label_singular: News post
    folder: content/news
    create: true
    slug: "{{slug}}"
    format: yaml-frontmatter
    # Exclude the Hugo section index (content/news/_index.<lang>.md): it lacks `type`.
    filter: { field: type, value: post }
    i18n: true
    fields:
      - { label: Title, name: title, widget: string, i18n: true }
      - { label: Date, name: date, widget: datetime, i18n: duplicate }
      - { label: Type, name: type, widget: hidden, default: post }
      - { label: Body, name: body, widget: markdown, i18n: true }

  - name: pages
    label: Pages
    label_singular: Page
    folder: content/pages
    create: true
    slug: "{{slug}}"
    format: yaml-frontmatter
    i18n: true
    fields:
      - { label: Title, name: title, widget: string, i18n: true }
      - { label: Body, name: body, widget: markdown, i18n: true }
```

- [ ] **Step 5: Run the test to confirm it passes (GREEN)**

Run: `bash scripts/check-build.sh`
Expected: `check-build: OK …`. (`public/admin/index.html` and `public/admin/config.yml` exist; the config greps match — these are static files, so text is verbatim.)

- [ ] **Step 6: Sanity-check the YAML parses**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('static/admin/config.yml')); print('config.yml: valid YAML')"`
Expected: `config.yml: valid YAML`.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "cms: add Decap admin (github backend via orchestrator OAuth bridge, i18n, editorial workflow)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3 — Configurable txn-cookie path in the OIDC module (Repo B)

**Repo:** orchestrator (`/Users/david/projects/outsources/mastersinternational.org/bots/orchestrator`)

**Files:**
- Modify: `internal/oidcauth/auth.go`
- Test: `internal/oidcauth/auth_test.go`

**Interfaces:**
- Produces: `oidcauth.Authenticator` gains an exported field `CookiePath string` (defaults to `"/auth"`); `LoginHandler` sets the txn cookie at that path. Task 4 sets `CookiePath: "/cms"` so the CMS txn cookie is scoped to `/cms/*` and never collides with the member-proxy `/auth/*` flow. Existing behavior is unchanged when `CookiePath` is empty.

- [ ] **Step 1: Write the failing tests (RED)**

Append to `internal/oidcauth/auth_test.go`:

```go
func TestLoginCookiePathDefaultsToAuth(t *testing.T) {
	a := &Authenticator{OAuth: &fakeOAuth{}, Verifier: &fakeVerifier{}}
	rw := httptest.NewRecorder()
	a.LoginHandler(rw, httptest.NewRequest("GET", "/auth/login", nil))
	cookies := rw.Result().Cookies()
	if len(cookies) == 0 {
		t.Fatal("expected txn cookie")
	}
	if cookies[0].Path != "/auth" {
		t.Errorf("default cookie path = %q, want /auth", cookies[0].Path)
	}
}

func TestLoginCookiePathHonorsOverride(t *testing.T) {
	a := &Authenticator{OAuth: &fakeOAuth{}, Verifier: &fakeVerifier{}, CookiePath: "/cms"}
	rw := httptest.NewRecorder()
	a.LoginHandler(rw, httptest.NewRequest("GET", "/auth/login", nil))
	cookies := rw.Result().Cookies()
	if len(cookies) == 0 {
		t.Fatal("expected txn cookie")
	}
	if cookies[0].Path != "/cms" {
		t.Errorf("override cookie path = %q, want /cms", cookies[0].Path)
	}
}
```

- [ ] **Step 2: Run the tests to confirm they fail**

Run: `go test ./internal/oidcauth/ -run TestLoginCookiePath -v`
Expected: compile error — `unknown field 'CookiePath' in struct literal` (the field does not exist yet).

- [ ] **Step 3: Add the field and use it**

In `internal/oidcauth/auth.go`, change the `Authenticator` struct to:

```go
type Authenticator struct {
	OAuth      oauth2Config
	Verifier   idVerifier
	TxnCookie  string // defaults to "bots_txn"
	CookiePath string // defaults to "/auth"
}
```

Add this helper next to `txnName()`:

```go
func (a *Authenticator) cookiePath() string {
	if a.CookiePath == "" {
		return "/auth"
	}
	return a.CookiePath
}
```

In `LoginHandler`, change the cookie's `Path` from the literal `"/auth"` to `a.cookiePath()`:

```go
	http.SetCookie(w, &http.Cookie{
		Name: a.txnName(), Value: base64URL(raw), Path: a.cookiePath(),
		HttpOnly: true, Secure: true, SameSite: http.SameSiteLaxMode, MaxAge: 600,
	})
```

- [ ] **Step 4: Run the tests to confirm they pass (GREEN) + no regression**

Run: `go test ./internal/oidcauth/ -v`
Expected: PASS, including the pre-existing `TestLoginRedirectsAndSetsTxnCookie`, `TestCallbackVerifiesAndReturnsClaims`, `TestCallbackStateMismatchRejected`. Output pristine.

- [ ] **Step 5: Commit (in Repo B)**

```bash
git -C /Users/david/projects/outsources/mastersinternational.org add bots/orchestrator/internal/oidcauth/
git -C /Users/david/projects/outsources/mastersinternational.org commit -m "oidcauth: configurable txn cookie path (default /auth) for the CMS bridge

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4 — The Decap OAuth bridge package (Repo B)

**Repo:** orchestrator

**Files:**
- Create: `internal/cmsauth/cmsauth.go`
- Test: `internal/cmsauth/cmsauth_test.go`

**Interfaces:**
- Consumes: `oidcauth.Authenticator` (with `CookiePath` from Task 3, `LoginHandler`, `Exchange`, `Claims`); `identity.IsMember(userRoles, memberRoles []string) bool`.
- Produces: `cmsauth.New(auth *oidcauth.Authenticator, allowedRoles []string, githubPAT string) *Handler` with methods `AuthStart(w, r)` and `Callback(w, r)`. Task 5 constructs the `Authenticator` (CMS Zitadel app, `TxnCookie:"cms_txn"`, `CookiePath:"/cms"`), passes the allowed roles and the bot PAT, and registers the two methods at `/cms/auth` and `/cms/callback`.

**Protocol contract (verified against Decap source — implement exactly):** On `/cms/auth`, redirect (302) the popup into the Zitadel auth-code+PKCE flow. On `/cms/callback`, after Zitadel returns, serve an HTML page that performs Decap's external-OAuth handshake: it posts `authorizing:github` to `window.opener`, waits for Decap's echo, then posts the result. Success result string = `authorization:github:success:` + `{"token":"<PAT>","provider":"github"}`. Error result string = `authorization:github:error:` + a JSON-encoded message. The popup origin equals `base_url` (it is served from `bots.mastersinternationalschool.org`), which is what Decap's listener requires.

- [ ] **Step 1: Write the failing tests (RED)**

Create `internal/cmsauth/cmsauth_test.go`:

```go
package cmsauth

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"golang.org/x/oauth2"

	"mis/bots-orchestrator/internal/oidcauth"
)

// Fakes implement oidcauth's (unexported) interfaces structurally via exported
// methods, so they are assignable to the exported OAuth / Verifier fields.
type fakeOAuth struct{}

func (fakeOAuth) AuthCodeURL(state string, _ ...oauth2.AuthCodeOption) string {
	return "https://idp/authorize?state=" + state
}
func (fakeOAuth) Exchange(_ context.Context, _ string, _ ...oauth2.AuthCodeOption) (*oauth2.Token, error) {
	tok := &oauth2.Token{AccessToken: "at"}
	return tok.WithExtra(map[string]any{"id_token": "rawid"}), nil
}

type fakeVerifier struct{ roles []string }

func (f fakeVerifier) Verify(_ context.Context, _ string, _ string) (oidcauth.Claims, error) {
	return oidcauth.Claims{Sub: "u1", Roles: f.roles}, nil
}

func newHandler(roles []string) *Handler {
	a := &oidcauth.Authenticator{
		OAuth:      fakeOAuth{},
		Verifier:   fakeVerifier{roles: roles},
		TxnCookie:  "cms_txn",
		CookiePath: "/cms",
	}
	return New(a, []string{"cms-superadmin", "cms-editor", "cms-admissions", "cms-hr"}, "ghp_testpat")
}

// driveCallback runs AuthStart to obtain the txn cookie + state, then calls
// Callback with a matching code+state, returning the rendered HTML body.
func driveCallback(t *testing.T, h *Handler) string {
	t.Helper()
	lw := httptest.NewRecorder()
	h.AuthStart(lw, httptest.NewRequest("GET", "/cms/auth", nil))
	if lw.Code != http.StatusFound {
		t.Fatalf("AuthStart code = %d, want 302", lw.Code)
	}
	cookies := lw.Result().Cookies()
	if len(cookies) == 0 || cookies[0].Path != "/cms" {
		t.Fatalf("expected cms_txn cookie at /cms, got %+v", cookies)
	}
	loc := lw.Header().Get("Location")
	state := strings.TrimPrefix(loc, "https://idp/authorize?state=")
	req := httptest.NewRequest("GET", "/cms/callback?code=abc&state="+state, nil)
	req.AddCookie(cookies[0])
	rw := httptest.NewRecorder()
	h.Callback(rw, req)
	if ct := rw.Header().Get("Content-Type"); !strings.HasPrefix(ct, "text/html") {
		t.Errorf("Content-Type = %q, want text/html", ct)
	}
	if cc := rw.Header().Get("Cache-Control"); cc != "no-store" {
		t.Errorf("Cache-Control = %q, want no-store", cc)
	}
	return rw.Body.String()
}

func TestCallbackAuthorizedReturnsToken(t *testing.T) {
	body := driveCallback(t, newHandler([]string{"cms-editor"}))
	if !strings.Contains(body, "authorization:github:success:") {
		t.Errorf("expected success handshake, got:\n%s", body)
	}
	if !strings.Contains(body, "ghp_testpat") {
		t.Errorf("expected the bot PAT in the success payload")
	}
	if strings.Contains(body, "authorization:github:error:") {
		t.Errorf("authorized login must not emit an error handshake")
	}
}

func TestCallbackForbiddenForNonCMSRole(t *testing.T) {
	body := driveCallback(t, newHandler([]string{"parents"}))
	if !strings.Contains(body, "authorization:github:error:") {
		t.Errorf("expected error handshake for non-CMS role, got:\n%s", body)
	}
	if strings.Contains(body, "ghp_testpat") {
		t.Errorf("the bot PAT must NEVER be sent to a non-CMS user")
	}
}

func TestCallbackBadStateReturnsError(t *testing.T) {
	h := newHandler([]string{"cms-editor"})
	lw := httptest.NewRecorder()
	h.AuthStart(lw, httptest.NewRequest("GET", "/cms/auth", nil))
	cookie := lw.Result().Cookies()[0]
	req := httptest.NewRequest("GET", "/cms/callback?code=abc&state=WRONG", nil)
	req.AddCookie(cookie)
	rw := httptest.NewRecorder()
	h.Callback(rw, req)
	body := rw.Body.String()
	if !strings.Contains(body, "authorization:github:error:") {
		t.Errorf("state mismatch must produce an error handshake")
	}
	if strings.Contains(body, "ghp_testpat") {
		t.Errorf("the bot PAT must NEVER be sent when auth fails")
	}
}
```

- [ ] **Step 2: Run the tests to confirm they fail**

Run: `go test ./internal/cmsauth/ -v`
Expected: build failure — `internal/cmsauth/cmsauth.go` does not exist (`undefined: New`, `undefined: Handler`).

- [ ] **Step 3: Implement the bridge**

Create `internal/cmsauth/cmsauth.go`:

```go
// Package cmsauth bridges a Zitadel OIDC login to the Decap CMS external-OAuth
// handshake. On a successful login by a user holding an allowed CMS role, it
// hands the shared GitHub bot PAT to the Decap admin window via window.postMessage.
// Decap treats that token as an opaque GitHub bearer, so a pre-existing
// fine-grained PAT is a valid thing to return.
package cmsauth

import (
	"encoding/json"
	"net/http"

	"mis/bots-orchestrator/internal/identity"
	"mis/bots-orchestrator/internal/oidcauth"
)

type Handler struct {
	auth         *oidcauth.Authenticator
	allowedRoles []string
	githubPAT    string
}

func New(auth *oidcauth.Authenticator, allowedRoles []string, githubPAT string) *Handler {
	return &Handler{auth: auth, allowedRoles: allowedRoles, githubPAT: githubPAT}
}

// AuthStart begins the Zitadel auth-code+PKCE flow. Decap opens this in a popup;
// we ignore Decap's query params and run our own OIDC flow. The txn cookie is
// scoped to /cms by the Authenticator's CookiePath.
func (h *Handler) AuthStart(w http.ResponseWriter, r *http.Request) {
	h.auth.LoginHandler(w, r)
}

// Callback completes the flow, gates on CMS roles, and renders the Decap
// handshake page with either the bot PAT (success) or an error.
func (h *Handler) Callback(w http.ResponseWriter, r *http.Request) {
	claims, err := h.auth.Exchange(r)
	if err != nil {
		writeHandshake(w, errorResult("authentication failed"))
		return
	}
	if !identity.IsMember(claims.Roles, h.allowedRoles) {
		writeHandshake(w, errorResult("your account is not authorized for the CMS"))
		return
	}
	writeHandshake(w, successResult(h.githubPAT))
}

func successResult(token string) string {
	payload, _ := json.Marshal(map[string]string{"token": token, "provider": "github"})
	return "authorization:github:success:" + string(payload)
}

func errorResult(message string) string {
	payload, _ := json.Marshal(message) // JSON string literal
	return "authorization:github:error:" + string(payload)
}

// writeHandshake renders the Decap external-OAuth popup page. The result string
// is embedded as a JSON-encoded (HTML/JS-safe) literal: json.Marshal escapes
// < > & and quotes, so no <script> breakout or injection is possible.
func writeHandshake(w http.ResponseWriter, result string) {
	resultJS, _ := json.Marshal(result)
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(`<!DOCTYPE html><html><head><meta charset="utf-8"></head><body><script>
(function () {
  var result = ` + string(resultJS) + `;
  function receive(e) {
    window.removeEventListener("message", receive, false);
    if (window.opener) { window.opener.postMessage(result, e.origin); }
    window.close();
  }
  window.addEventListener("message", receive, false);
  if (window.opener) { window.opener.postMessage("authorizing:github", "*"); }
})();
</script></body></html>`))
}
```

- [ ] **Step 4: Run the tests to confirm they pass (GREEN)**

Run: `go test ./internal/cmsauth/ -v`
Expected: PASS for `TestCallbackAuthorizedReturnsToken`, `TestCallbackForbiddenForNonCMSRole`, `TestCallbackBadStateReturnsError`. Output pristine.

- [ ] **Step 5: Commit (Repo B)**

```bash
git -C /Users/david/projects/outsources/mastersinternational.org add bots/orchestrator/internal/cmsauth/
git -C /Users/david/projects/outsources/mastersinternational.org commit -m "cmsauth: Decap CMS OAuth bridge (Zitadel cms-* gate -> bot PAT via postMessage)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5 — Config, wiring, and route registration (Repo B)

**Repo:** orchestrator

**Files:**
- Modify: `internal/config/config.go`
- Test: `internal/config/config_test.go`
- Modify: `cmd/orchestrator/main.go`
- Modify: `internal/server/server.go`
- Test: `internal/server/server_test.go`
- Modify: `bots/orchestrator/bots.yaml.example`
- Modify: `bots/.env.example`

**Interfaces:**
- Consumes: `cmsauth.New`/`*cmsauth.Handler` (Task 4); `oidcauth.NewZitadel`, `Authenticator{TxnCookie, CookiePath}` (Task 3).
- Produces: an optional `cms:` config block (`config.CMSConfig` + `Config.CMSEnabled()`); when enabled, `main.go` builds a CMS `Authenticator` and `cmsauth.Handler` and injects it via `server.Deps.CMS`; `server.Handler()` serves `/cms/auth` + `/cms/callback`.

- [ ] **Step 1: Write the failing config tests (RED)**

Append to `internal/config/config_test.go`:

```go
func TestLoadResolvesCMSSecretsAndDefaults(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "bots.yaml")
	if err := os.WriteFile(p, []byte(`
oidc: { issuer: "i", client_id: "c", client_secret_env: "BOTS_OIDC_SECRET", redirect_url: "r" }
session: { cookie_name: "s", secret_env: "BOTS_SESSION_SECRET", ttl_seconds: 1 }
cms:
  issuer: "https://auth.mastersinternationalschool.org"
  client_id: "mis-website-cms"
  client_secret_env: "CMS_OIDC_SECRET"
  redirect_url: "https://bots.mastersinternationalschool.org/cms/callback"
  github_pat_env: "WEBSITE_CMS_GITHUB_PAT"
`), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("BOTS_OIDC_SECRET", "x")
	t.Setenv("BOTS_SESSION_SECRET", "0123456789abcdef0123456789abcdef")
	t.Setenv("CMS_OIDC_SECRET", "cms-secret")
	t.Setenv("WEBSITE_CMS_GITHUB_PAT", "ghp_xyz")

	c, err := Load(p)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if !c.CMSEnabled() {
		t.Fatal("CMSEnabled() = false, want true")
	}
	if c.CMS.ClientSecret != "cms-secret" || c.CMS.GithubPAT != "ghp_xyz" {
		t.Errorf("cms secrets not resolved: secret=%q pat=%q", c.CMS.ClientSecret, c.CMS.GithubPAT)
	}
	wantRoles := []string{"cms-superadmin", "cms-editor", "cms-admissions", "cms-hr"}
	if len(c.CMS.AllowedRoles) != len(wantRoles) {
		t.Fatalf("allowed_roles = %v, want default %v", c.CMS.AllowedRoles, wantRoles)
	}
	for i := range wantRoles {
		if c.CMS.AllowedRoles[i] != wantRoles[i] {
			t.Errorf("allowed_roles[%d] = %q, want %q", i, c.CMS.AllowedRoles[i], wantRoles[i])
		}
	}
	wantScopes := []string{"openid", "email", "profile", "urn:zitadel:iam:org:project:roles"}
	if len(c.CMS.Scopes) != len(wantScopes) {
		t.Errorf("cms scopes = %v, want default %v", c.CMS.Scopes, wantScopes)
	}
}

func TestLoadCMSDisabledWhenAbsent(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "bots.yaml")
	if err := os.WriteFile(p, []byte(`
oidc: { issuer: "i", client_id: "c", client_secret_env: "BOTS_OIDC_SECRET", redirect_url: "r" }
session: { cookie_name: "s", secret_env: "BOTS_SESSION_SECRET", ttl_seconds: 1 }
`), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("BOTS_OIDC_SECRET", "x")
	t.Setenv("BOTS_SESSION_SECRET", "0123456789abcdef0123456789abcdef")
	// Deliberately leave CMS_OIDC_SECRET / WEBSITE_CMS_GITHUB_PAT unset.
	c, err := Load(p)
	if err != nil {
		t.Fatalf("Load must succeed with no cms section: %v", err)
	}
	if c.CMSEnabled() {
		t.Error("CMSEnabled() = true, want false when cms section absent")
	}
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `go test ./internal/config/ -run CMS -v`
Expected: compile error — `c.CMSEnabled undefined` / `c.CMS undefined`.

- [ ] **Step 3: Add the CMS config**

In `internal/config/config.go`, add the field to `Config`:

```go
type Config struct {
	Listen    string          `yaml:"listen"`
	OIDC      OIDCConfig      `yaml:"oidc"`
	Session   SessionConfig   `yaml:"session"`
	RBAC      RBACConfig      `yaml:"rbac"`
	Instances InstancesConfig `yaml:"instances"`
	CMS       CMSConfig       `yaml:"cms"`
}
```

Add the type (next to the other config types):

```go
type CMSConfig struct {
	Issuer          string   `yaml:"issuer"`
	ClientID        string   `yaml:"client_id"`
	ClientSecretEnv string   `yaml:"client_secret_env"`
	ClientSecret    string   `yaml:"-"`
	RedirectURL     string   `yaml:"redirect_url"`
	Scopes          []string `yaml:"scopes"`
	AllowedRoles    []string `yaml:"allowed_roles"`
	GithubPATEnv    string   `yaml:"github_pat_env"`
	GithubPAT       string   `yaml:"-"`
}
```

In `Load`, after the existing session-secret resolution and before the scopes default (i.e. before `return &c, nil`), add the optional CMS resolution:

```go
	if c.CMS.ClientID != "" {
		if c.CMS.ClientSecret, err = requireEnv(c.CMS.ClientSecretEnv); err != nil {
			return nil, err
		}
		if c.CMS.GithubPAT, err = requireEnv(c.CMS.GithubPATEnv); err != nil {
			return nil, err
		}
		if len(c.CMS.Scopes) == 0 {
			c.CMS.Scopes = []string{"openid", "email", "profile", "urn:zitadel:iam:org:project:roles"}
		}
		if len(c.CMS.AllowedRoles) == 0 {
			c.CMS.AllowedRoles = []string{"cms-superadmin", "cms-editor", "cms-admissions", "cms-hr"}
		}
	}
```

Add the predicate (at the end of the file):

```go
// CMSEnabled reports whether the Decap CMS OAuth bridge is configured.
func (c *Config) CMSEnabled() bool { return c.CMS.ClientID != "" }
```

- [ ] **Step 4: Run config tests (GREEN)**

Run: `go test ./internal/config/ -v`
Expected: PASS for the new CMS tests and all pre-existing config tests. Pristine.

- [ ] **Step 5: Add the failing server-wiring test (RED)**

Append to `internal/server/server_test.go` (and add `"context"`, `"golang.org/x/oauth2"`, `"mis/bots-orchestrator/internal/cmsauth"`, `"mis/bots-orchestrator/internal/oidcauth"` to its imports):

```go
type srvCMSOAuth struct{}

func (srvCMSOAuth) AuthCodeURL(state string, _ ...oauth2.AuthCodeOption) string {
	return "https://idp/authorize?state=" + state
}
func (srvCMSOAuth) Exchange(context.Context, string, ...oauth2.AuthCodeOption) (*oauth2.Token, error) {
	return nil, nil
}

type srvCMSVerifier struct{}

func (srvCMSVerifier) Verify(context.Context, string, string) (oidcauth.Claims, error) {
	return oidcauth.Claims{}, nil
}

func TestCMSAuthRouteGoesToBridgeNotProxy(t *testing.T) {
	s := newTestServer(t)
	s.cms = cmsauth.New(
		&oidcauth.Authenticator{OAuth: srvCMSOAuth{}, Verifier: srvCMSVerifier{}, CookiePath: "/cms"},
		[]string{"cms-editor"}, "ghp_x",
	)
	rw := httptest.NewRecorder()
	s.Handler().ServeHTTP(rw, httptest.NewRequest("GET", "/cms/auth", nil))
	if rw.Code != http.StatusFound {
		t.Fatalf("/cms/auth code = %d, want 302", rw.Code)
	}
	// Must redirect to the IdP, NOT to the member-proxy login (which the /* proxy would do).
	if loc := rw.Header().Get("Location"); !strings.HasPrefix(loc, "https://idp/") {
		t.Fatalf("/cms/auth Location = %q, want IdP redirect", loc)
	}
}
```

Add `"strings"` to the server_test imports if not present.

- [ ] **Step 6: Run to confirm failure**

Run: `go test ./internal/server/ -run TestCMSAuthRoute -v`
Expected: compile error — `s.cms undefined` (field not added yet).

- [ ] **Step 7: Wire the CMS handler into the server**

In `internal/server/server.go`, add the import `"mis/bots-orchestrator/internal/cmsauth"`. Add the field to `Server`:

```go
type Server struct {
	auth          *oidcauth.Authenticator
	cms           *cmsauth.Handler
	sessions      *session.Manager
	memberRoles   []string
	registry      *registry.Registry
	loginPath     string
	ensure        ensureFn
	serveInstance serveFn

	spawnMu sync.Map
}
```

Register the routes in `Handler()` before the `/*` catch-all:

```go
func (s *Server) Handler() http.Handler {
	r := chi.NewRouter()
	if s.auth != nil {
		r.Get("/auth/login", s.auth.LoginHandler)
		r.Get("/auth/callback", s.handleCallback)
	}
	r.Get("/auth/logout", s.handleLogout)
	if s.cms != nil {
		r.Get("/cms/auth", s.cms.AuthStart)
		r.Get("/cms/callback", s.cms.Callback)
	}
	r.HandleFunc("/*", s.handleProxy)
	return r
}
```

Add `CMS` to `Deps` and assign it in `NewProduction`:

```go
type Deps struct {
	Auth          *oidcauth.Authenticator
	CMS           *cmsauth.Handler
	Sessions      *session.Manager
	MemberRoles   []string
	Registry      *registry.Registry
	LoginPath     string
	Ensure        ensureFn
	ServeInstance serveFn
}

func NewProduction(d Deps) *Server {
	return &Server{
		auth:          d.Auth,
		cms:           d.CMS,
		sessions:      d.Sessions,
		memberRoles:   d.MemberRoles,
		registry:      d.Registry,
		loginPath:     d.LoginPath,
		ensure:        d.Ensure,
		serveInstance: d.ServeInstance,
	}
}
```

- [ ] **Step 8: Run server tests (GREEN)**

Run: `go test ./internal/server/ -v`
Expected: PASS for `TestCMSAuthRouteGoesToBridgeNotProxy` and the three pre-existing server tests. Pristine.

- [ ] **Step 9: Wire the CMS bridge in main**

In `cmd/orchestrator/main.go`, add the import `"mis/bots-orchestrator/internal/cmsauth"`. After the `session.New(...)` block and before `reg := registry.New(...)`, add:

```go
	var cmsHandler *cmsauth.Handler
	if cfg.CMSEnabled() {
		cmsAuth, err := oidcauth.NewZitadel(ctx, cfg.CMS.Issuer, cfg.CMS.ClientID,
			cfg.CMS.ClientSecret, cfg.CMS.RedirectURL, cfg.CMS.Scopes)
		if err != nil {
			log.Fatalf("cms oidc: %v", err)
		}
		cmsAuth.TxnCookie = "cms_txn"
		cmsAuth.CookiePath = "/cms"
		cmsHandler = cmsauth.New(cmsAuth, cfg.CMS.AllowedRoles, cfg.CMS.GithubPAT)
		log.Printf("cms oauth bridge enabled (roles=%v)", cfg.CMS.AllowedRoles)
	}
```

Add `CMS: cmsHandler,` to the `server.Deps{...}` literal (right after `Auth: auth,`).

- [ ] **Step 10: Build + full suite (GREEN)**

Run: `go build ./... && go test ./...`
Expected: build succeeds; every package passes; output pristine.

- [ ] **Step 11: Update the example config files (no secrets)**

Append to `bots/orchestrator/bots.yaml.example`:

```yaml
# Decap CMS OAuth bridge (optional; omit the whole `cms:` block to disable).
# When present, the orchestrator serves /cms/auth and /cms/callback on the same
# host (https://bots.mastersinternationalschool.org). Reuses the same Zitadel
# issuer; uses its OWN app `mis-website-cms` and a fine-grained GitHub PAT.
cms:
  issuer: "https://auth.mastersinternationalschool.org"
  client_id: "mis-website-cms"            # from the Zitadel app create (runbook Task 7)
  client_secret_env: "CMS_OIDC_SECRET"
  redirect_url: "https://bots.mastersinternationalschool.org/cms/callback"
  scopes: ["openid", "email", "profile", "urn:zitadel:iam:org:project:roles"]
  allowed_roles: ["cms-superadmin", "cms-editor", "cms-admissions", "cms-hr"]
  github_pat_env: "WEBSITE_CMS_GITHUB_PAT"
```

In `bots/.env.example`, add (KEYS only, no values) — note the first two were missing and are required by the orchestrator itself:

```bash
# orchestrator (Zitadel member-proxy + session)
BOTS_OIDC_SECRET=
BOTS_SESSION_SECRET=

# Decap CMS OAuth bridge
CMS_OIDC_SECRET=
WEBSITE_CMS_GITHUB_PAT=
```

- [ ] **Step 12: Commit (Repo B)**

```bash
git -C /Users/david/projects/outsources/mastersinternational.org add bots/
git -C /Users/david/projects/outsources/mastersinternational.org commit -m "orchestrator: wire optional Decap CMS OAuth bridge (/cms/auth, /cms/callback)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

# Deployment & Integration Runbook (Tasks 6–9 — MANUAL)

These touch live infrastructure, secrets, and a browser. The human operator runs them after Tasks 1–5 are merged. Each step has an explicit verification.

## Task 6 — Mint the fine-grained GitHub PAT (browser, one-time)

- [ ] In the browser, go to **GitHub → Settings → Developer settings → Fine-grained personal access tokens → Generate new token** (or the `it-of-mis` org's fine-grained PAT page if org policy routes it there).
- [ ] **Resource owner:** `it-of-mis`. **Repository access:** *Only select repositories* → **`it-of-mis/website`**.
- [ ] **Repository permissions:** **Contents: Read and write**; **Pull requests: Read and write**; **Metadata: Read-only** (auto-selected). Nothing else.
- [ ] Expiration per policy (e.g. 90 days; set a renewal reminder). Generate; copy the `github_pat_…` value.
- [ ] If `it-of-mis` enforces SSO, **authorize the token for the org** (token page → "Configure SSO").
- [ ] **Verify** (replace `<PAT>`):
  ```bash
  curl -s -H "Authorization: token <PAT>" https://api.github.com/repos/it-of-mis/website | jq '.permissions'
  ```
  Expected: `"push": true` (and `pull`/`admin` as applicable). Also `curl -s -o /dev/null -w '%{http_code}' -H "Authorization: token <PAT>" https://api.github.com/user` → `200`.
- [ ] Hold the value for Task 8 (it goes into the box `.env` as `WEBSITE_CMS_GITHUB_PAT` — never into a repo).

## Task 7 — Create the Zitadel app `mis-website-cms` (management API)

- [ ] Confirm the test editor account holds a CMS role grant on the project (else the roles claim will be empty). If needed, grant it (e.g. `cms-editor`) via the console or `POST /management/v1/users/{userId}/grants`.
- [ ] From the Zitadel resources repo, using the automation PAT:
  ```bash
  cd /Users/david/projects/outsources/mastersinternational.org
  ISSUER=https://auth.mastersinternationalschool.org
  PROJECT_ID=375950440665186306
  TOKEN="$(cat zitadel/.pat)"
  # Verify the PAT is still valid (it may be stale post-reinit):
  curl -s -H "Authorization: Bearer $TOKEN" "$ISSUER/management/v1/orgs/me" | jq '.org.id'   # expect "375822041443532802"
  ```
  If that returns 401/unauthenticated, regenerate the token via the headless fallback documented in `zitadel/website-oidc-resources.md` before continuing.
- [ ] Create the confidential web app (PKCE layered on top, matching the existing apps):
  ```bash
  curl -s -X POST "$ISSUER/management/v1/projects/$PROJECT_ID/apps/oidc" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d '{
      "name": "mis-website-cms",
      "redirectUris": ["https://bots.mastersinternationalschool.org/cms/callback"],
      "postLogoutRedirectUris": ["https://it-of-mis.github.io/website/admin/"],
      "responseTypes": ["OIDC_RESPONSE_TYPE_CODE"],
      "grantTypes": ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"],
      "appType": "OIDC_APP_TYPE_WEB",
      "authMethodType": "OIDC_AUTH_METHOD_TYPE_BASIC",
      "version": "OIDC_VERSION_1_0",
      "devMode": false,
      "accessTokenType": "OIDC_TOKEN_TYPE_BEARER",
      "accessTokenRoleAssertion": true,
      "idTokenRoleAssertion": true,
      "idTokenUserinfoAssertion": true
    }' | jq '{clientId, clientSecret}'
  ```
- [ ] Record `clientId` → goes in the box `bots.yaml` `cms.client_id`. Record `clientSecret` → goes in the box `.env` as `CMS_OIDC_SECRET`. Append both to the gitignored `zitadel/website-oidc-resources.md` record (secret stays only in the gitignored secret store; never in either website/orchestrator repo).

## Task 8 — Deploy the orchestrator to the box

- [ ] SSH in: `ssh -i ~/.ssh/nanobot-ops.pem -p 1022 ubuntu@18.141.228.49`. Determine arch (`uname -m`) for the build target.
- [ ] Get the updated orchestrator source onto the box (rsync the `bots/orchestrator/` tree) and build there if Go is installed:
  ```bash
  cd ~/bots/orchestrator && go build -o bots-orchestrator ./cmd/orchestrator
  ```
  If Go is absent on the box, cross-compile locally and copy the binary (e.g. `GOOS=linux GOARCH=amd64 go build -o bots-orchestrator ./cmd/orchestrator` for x86_64; use `arm64` if `uname -m` says `aarch64`), then `scp -P 1022 -i ~/.ssh/nanobot-ops.pem bots-orchestrator ubuntu@18.141.228.49:~/bots/orchestrator/`.
- [ ] Edit `~/bots/orchestrator/bots.yaml` — add the `cms:` section from `bots.yaml.example`, with `client_id` from Task 7.
- [ ] Edit `~/bots/.env` — set: `BOTS_SESSION_SECRET=$(openssl rand -hex 32)` (64 chars); `CMS_OIDC_SECRET=<from Task 7>`; `WEBSITE_CMS_GITHUB_PAT=<from Task 6>`. Set `BOTS_OIDC_SECRET=` to the member-proxy app secret if it exists, else any non-empty placeholder — the orchestrator starts with a placeholder and the CMS endpoints work independently; just do NOT exercise `/auth/login` until the `mis-bots-orchestrator` app is real.
- [ ] Install + start the unit:
  ```bash
  sudo cp ~/bots/systemd/bots-orchestrator.service /etc/systemd/system/
  sudo systemctl daemon-reload && sudo systemctl enable --now bots-orchestrator
  journalctl -u bots-orchestrator -n 30 --no-pager   # expect "listening on 127.0.0.1:8088" + "cms oauth bridge enabled"
  ```
- [ ] Confirm Caddy fronts `bots.mastersinternationalschool.org` → `127.0.0.1:8088` (the `Caddyfile.example` block is applied). Reload Caddy if you edited it.
- [ ] **Verify reachability:**
  ```bash
  curl -sI https://bots.mastersinternationalschool.org/cms/auth | head -n5
  ```
  Expected: `HTTP/2 302` with a `location:` to `https://auth.mastersinternationalschool.org/oauth/v2/authorize?...` (the Zitadel authorize URL, with `code_challenge` and `redirect_uri=https://bots.mastersinternationalschool.org/cms/callback`).

## Task 9 — End-to-end acceptance (the Phase 2 done criterion)

- [ ] Ensure Tasks 1–2 are merged to `it-of-mis/website` `main` and Pages has redeployed; confirm **no PR-review branch protection is required on `main`** (Decap's "Publish" merges the PR using the bot PAT — a required-review rule would block it).
- [ ] Open **https://it-of-mis.github.io/website/admin/**. Decap loads, shows "Login with GitHub".
- [ ] Click login → a popup opens `/cms/auth` → redirects to Zitadel → log in as a **`cms-editor`** user → consent. The popup posts the token back; Decap shows the authenticated dashboard with the **News** and **Pages** collections. (The existing `welcome` post appears under News; `_index` does NOT.)
- [ ] Edit the `welcome` post (change a word in each locale) or create a new News post (set a Latin slug for zh/th) → **Save** (draft).
- [ ] On `it-of-mis/website`, confirm a branch **`cms/news/<slug>`** and an open **PR** appear, labelled **`decap-cms/draft`**, containing `<slug>.en.md`, `.zh.md`, `.th.md` (with `type: post`).
- [ ] In Decap set the entry to **Ready → Publish**. Decap merges the PR to `main`; the deploy workflow runs; the change renders at `/website/news/<slug>/` (and `/website/zh/news/<slug>/`, `/website/th/news/<slug>/`).
- [ ] **Negative check:** in a fresh session, log in as a non-CMS user (e.g. a `parents`-only account). The popup returns the error handshake; Decap reports the account is not authorized; no repo write occurs.
- [ ] Update `CLAUDE.md` "Verified infrastructure" with the new facts (the `mis-website-cms` Zitadel app, the `/cms/*` orchestrator endpoints, that the bridge is live).

---

## Risks & decisions (carry into review)

- **Bot PAT is exposed to each editor's browser.** Decap stores the returned token client-side and an editor could extract it to push directly, bypassing the editorial workflow. Accepted for v1 per the spec: the PAT is scoped to the single public content repo and only `cms-*` SSO users receive it (their blast radius equals what they're already authorized to do). Upgrade path: a GitHub App with short-lived tokens.
- **No required-review branch protection on `main`.** The editorial-workflow "Publish" performs the merge with the bot PAT; a required-reviews rule would break it. Documented in Task 9.
- **Orchestrator deploy is manual** (no automated path; `deploy.sh` only handles the nanobot persona bots). Captured as Task 8.
- **The member-proxy Zitadel app (`mis-bots-orchestrator`) is not provisioned.** Phase 2 does not depend on it — the CMS bridge uses its own `mis-website-cms` app. The orchestrator starts with a placeholder member-proxy secret; `/auth/login` simply must not be used until that app exists.
- **Stale automation PAT / org SSO.** The Zitadel automation PAT may be stale (Task 7 verifies first); the GitHub PAT may need org-SSO authorization (Task 6).
- **`public_folder` under the Pages subpath.** Media uploads store root-relative `/uploads/...` paths; under the `/website/` subpath these don't resolve at runtime. Media is not a v1 focus; revisit at DNS cutover (when the site moves to the domain root the paths become correct).
- **Homepage editing deferred.** The homepage `_index.<lang>.md` is a special Hugo construct and is not a CMS collection in Phase 2 (per the locked decision). News + Pages prove the full loop.

## Verified-facts appendix (so implementers trust the exact values)

- **Orchestrator** (read verbatim): module `mis/bots-orchestrator`, Go 1.25, chi v5. `oidcauth.Authenticator{OAuth, Verifier, TxnCookie}` with `LoginHandler` (302 + txn cookie, currently `Path:/auth`) and `Exchange(r) (Claims, error)` (reads txn cookie, checks `state`, PKCE exchange, verifies id_token + nonce). `oidcauth.NewZitadel(ctx, issuer, clientID, clientSecret, redirectURL, scopes)`. `identity.IsMember(userRoles, memberRoles) bool`. Roles parsed from claim `urn:zitadel:iam:org:project:roles`. Routes registered in `server.Handler()`; `/*` is a session-gated proxy. Config = YAML (`BOTS_CONFIG`) + `*_env` → `os.Getenv` (hard-fail if empty); session secret must be ≥64 bytes. Caddy: `bots.mastersinternationalschool.org` → `127.0.0.1:8088`. Tests: `go test ./...`, interface-injected fakes.
- **Decap 3.14.1** (confirmed from source/docs): external-OAuth popup opens `${base_url}/${auth_endpoint}` (default `auth`); handshake = popup posts `authorizing:github` → Decap (origin must equal `base_url`) echoes → popup posts `authorization:github:success:{"token","provider"}` (or `:error:`). Token is an opaque GitHub bearer; a fine-grained PAT works. `editorial_workflow` → one branch `cms/<collection>/<slug>` + PR + label `decap-cms/draft`, one PR across all locales. `multiple_files` → `<folder>/<slug>.<locale>.md` (folder collections only). Folder collections enumerate all `.md` at depth 1 incl. `_index.*`; no native exclude → marker-field + `filter:{field,value}` (exact-match). `getConfigUrl()` defaults to relative `config.yml`. `editor.preview:false`, `format: yaml-frontmatter`, reserved `name: body`, `i18n: true|duplicate`.
- **Zitadel** (confirmed from the resources doc): issuer/org/project/roles per Global Constraints; existing apps are confidential WEB `client_secret_basic` with `idTokenRoleAssertion:true`; apps created via `POST /management/v1/projects/{id}/apps/oidc` with the `zitadel/.pat` bearer.
