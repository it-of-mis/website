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

# the about page (now a content/pages/ folder-collection entry for Decap editing) in every locale
assert_file public/pages/about/index.html
assert_file public/zh/pages/about/index.html
assert_file public/th/pages/about/index.html

# Decap CMS admin shipped as static files (Hugo copies static/ verbatim, no minify)
assert_file public/admin/index.html
assert_file public/admin/config.yml
# admin config binds to the right repo + OAuth bridge (static file: exact text, no minify)
assert_grep public/admin/config.yml 'repo: it-of-mis/website'
assert_grep public/admin/config.yml 'base_url: https://bots\.mastersinternationalschool\.org'
assert_grep public/admin/config.yml 'auth_endpoint: cms/auth'
assert_grep public/admin/config.yml 'publish_mode: editorial_workflow'

# correct lang attribute per locale.
# NOTE: `hugo --minify` strips quotes around attribute values (lang="en" -> lang=en),
# so every attribute assertion is quote-tolerant (ERE: "? = optional quote). Verified.
assert_grep public/index.html '<html lang="?en'
assert_grep public/zh/index.html '<html lang="?zh'
assert_grep public/th/index.html '<html lang="?th'

# the language switcher actually links the OTHER locales (deliverable, not just files).
# Pattern is baseURL-agnostic: matches /zh/ or /website/zh/ (Pages subpath case).
assert_grep public/index.html 'href="?[^"'"'"'"]*/zh/"?'
assert_grep public/index.html 'href="?[^"'"'"'"]*/th/"?'

# localized content actually rendered (visible text survives minify)
assert_grep public/index.html 'Masters International School'
assert_grep public/zh/news/welcome/index.html '欢迎'

if [ "$fail" -ne 0 ]; then echo "check-build: FAIL"; exit 1; fi
echo "check-build: OK — build + i18n routes + switcher + content verified"
