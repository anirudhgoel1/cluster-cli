#!/usr/bin/env bash
# audit.sh · bash counterpart of audit.ps1.
#
# Usage:
#   ./audit.sh <project-dir> [repo] [domain] [working-dir]
#   ./audit.sh ~/projects/pavilion anirudhgoel1/pavilion pavilion.anirudhgoel.xyz

set -e

PROJECT_DIR="${1:?Usage: ./audit.sh <project-dir> [repo] [domain] [working-dir] [type=webapp|admin]}"
REPO="${2:-}"
DOMAIN="${3:-}"
WORKING_DIR="${4:-.}"
PROJECT_TYPE="${5:-webapp}"   # webapp | admin | pure-worker
# webapp      · Workers Static Assets, needs PWA + og.png + _headers + [assets]
# admin       · Workers Static Assets but admin tool, skips PWA + og.png + icons
# pure-worker · server-rendered worker (no static assets), skips [assets]/_headers/PWA/og.png

if [ ! -d "$PROJECT_DIR" ]; then echo "✗ $PROJECT_DIR does not exist" >&2; exit 1; fi
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
WD="$PROJECT_DIR"
[ "$WORKING_DIR" != "." ] && WD="$PROJECT_DIR/$WORKING_DIR"

results=()  # "section|item|severity|pass(0/1)|note"
add() { results+=("$1|$2|$3|$4|$5"); }

file_exists() { [ -f "$1" ]; }
dir_exists()  { [ -d "$1" ]; }
file_contains() { [ -f "$1" ] && grep -qE "$2" "$1"; }
# asset_exists name [working_dir] — looks at common paths
asset_exists() {
  local name="$1"; local wd="${2:-$WD}"
  [ -f "$wd/$name" ] || [ -f "$wd/assets/$name" ] || [ -f "$wd/assets/icons/$name" ] || [ -f "$wd/icons/$name" ] || [ -f "$wd/public/$name" ] || [ -f "$wd/static/$name" ]
}

# A · Git / GitHub / CI
[ -d "$PROJECT_DIR/.git" ] && add A.1 "Git initialized" P0 1 "" || add A.1 "Git initialized" P0 0 ""
if [ -d "$PROJECT_DIR/.git" ]; then
  branch=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)
  [ "$branch" = "main" ] && add A.2 "Default branch is main" P0 1 "" || add A.2 "Default branch is main" P0 0 "current: $branch"
  unc=$(git -C "$PROJECT_DIR" status -s 2>/dev/null | wc -l)
  [ "$unc" -eq 0 ] && add A.3 "No uncommitted changes" P1 1 "" || add A.3 "No uncommitted changes" P1 0 "$unc files dirty"
fi
file_contains "$PROJECT_DIR/.gitignore" '\.wrangler/?' && add A.4 ".gitignore covers .wrangler/" P0 1 "" || add A.4 ".gitignore covers .wrangler/" P0 0 ""
file_contains "$PROJECT_DIR/.gitignore" '\.claude/?'   && add A.5 ".gitignore covers .claude/" P1 1 ""   || add A.5 ".gitignore covers .claude/" P1 0 ""
file_contains "$PROJECT_DIR/.gitignore" '\.env'        && add A.6 ".gitignore covers .env" P0 1 ""       || add A.6 ".gitignore covers .env" P0 0 ""
file_exists "$PROJECT_DIR/.github/workflows/deploy.yml" && add A.7 "deploy.yml present" P0 1 ""          || add A.7 "deploy.yml present" P0 0 ""
file_contains "$PROJECT_DIR/.github/workflows/deploy.yml" "anirudhgoel1/cluster-cli/\.github/workflows/_deploy-cf-worker\.yml" && add A.8 "deploy.yml uses cluster-cli reusable" P0 1 "" || add A.8 "deploy.yml uses cluster-cli reusable" P0 0 ""
file_contains "$PROJECT_DIR/.github/workflows/deploy.yml" "CLOUDFLARE_API_TOKEN" && file_contains "$PROJECT_DIR/.github/workflows/deploy.yml" "CLOUDFLARE_ACCOUNT_ID" && add A.9 "deploy.yml secrets block" P0 1 "" || add A.9 "deploy.yml secrets block" P0 0 ""

if [ -n "$REPO" ]; then
  if gh secret list -R "$REPO" 2>/dev/null | grep -q CLOUDFLARE_API_TOKEN; then add A.10 "CLOUDFLARE_API_TOKEN secret set" P0 1 ""; else add A.10 "CLOUDFLARE_API_TOKEN secret set" P0 0 ""; fi
  if gh secret list -R "$REPO" 2>/dev/null | grep -q CLOUDFLARE_ACCOUNT_ID; then add A.11 "CLOUDFLARE_ACCOUNT_ID secret set" P0 1 ""; else add A.11 "CLOUDFLARE_ACCOUNT_ID secret set" P0 0 ""; fi
  conc=$(gh run list -R "$REPO" --limit 1 --workflow=deploy.yml --json conclusion -q '.[0].conclusion' 2>/dev/null || echo missing)
  [ "$conc" = "success" ] && add A.12 "Latest CI run succeeded" P0 1 "" || add A.12 "Latest CI run succeeded" P0 0 "latest: $conc"
fi

# B · Cloudflare config
file_exists "$WD/wrangler.toml" && add B.1 "wrangler.toml present" P0 1 "" || add B.1 "wrangler.toml present" P0 0 ""
file_contains "$WD/wrangler.toml" "custom_domain\s*=\s*true" && add B.2 "wrangler.toml custom_domain" P0 1 "" || add B.2 "wrangler.toml custom_domain" P0 0 ""
if [ "$PROJECT_TYPE" = "pure-worker" ]; then
  add B.3 "wrangler.toml [assets] (skipped · pure worker)" P2 1 ""
  add B.6 "_headers (skipped · pure worker · headers go in code)" P2 1 ""
else
  file_contains "$WD/wrangler.toml" "\[assets\]"               && add B.3 "wrangler.toml [assets]" P0 1 "" || add B.3 "wrangler.toml [assets]" P0 0 ""
  file_exists "$WD/_headers"                                  && add B.6 "_headers present" P0 1 ""        || add B.6 "_headers present" P0 0 ""
fi

# C · SEO
if file_exists "$WD/index.html"; then
  file_contains "$WD/index.html" 'name="description"' && add C.1 "meta description" P0 1 "" || add C.1 "meta description" P0 0 ""
  file_contains "$WD/index.html" 'og:title'           && add C.2 "og:title" P0 1 ""         || add C.2 "og:title" P0 0 ""
  file_contains "$WD/index.html" 'og:image'           && add C.3 "og:image" P0 1 ""         || add C.3 "og:image" P0 0 ""
  file_contains "$WD/index.html" 'summary_large_image' && add C.4 "twitter:card large" P0 1 "" || add C.4 "twitter:card large" P0 0 ""
  file_contains "$WD/index.html" 'name="theme-color"' && add C.6 "theme-color meta" P0 1 "" || add C.6 "theme-color meta" P0 0 ""
fi
# SEO + PWA expected for webapps; admin tools skip these
if [ "$PROJECT_TYPE" = "webapp" ]; then
  asset_exists "og.png"         && add C.8 "og.png" P0 1 ""        || add C.8 "og.png" P0 0 ""
  asset_exists "icon-192.png"   && add C.10 "icon-192.png" P0 1 "" || add C.10 "icon-192.png" P0 0 ""
  asset_exists "icon-512.png"   && add C.11 "icon-512.png" P0 1 "" || add C.11 "icon-512.png" P0 0 ""

  # D · PWA
  file_exists "$WD/manifest.webmanifest" && add D.1 "manifest.webmanifest" P0 1 "" || add D.1 "manifest.webmanifest" P0 0 ""
  file_exists "$WD/sw.js"                && add D.5 "sw.js" P0 1 ""                || add D.5 "sw.js" P0 0 ""
else
  add C.8 "og.png (skipped · admin tool)" P2 1 ""
  add D.1 "manifest.webmanifest (skipped · admin tool)" P2 1 ""
fi

# F · Live URL
if [ -n "$DOMAIN" ]; then
  code=$(curl -s -o /dev/null -w "%{http_code}" "https://$DOMAIN/" || echo 000)
  if [[ "$code" =~ ^(200|301|307|401)$ ]]; then add F.1 "Live URL responds" P0 1 "HTTP $code"; else add F.1 "Live URL responds" P0 0 "HTTP $code"; fi
fi

# Output
echo ""
echo "═══ Hard-Checklist Audit · $PROJECT_DIR ═══"
echo ""

passed=0; total=0; p0_fail=0; p1_fail=0; p2_fail=0
last_section=""
for line in "${results[@]}"; do
  IFS='|' read -r sec item sev pass note <<< "$line"
  group="${sec%%.*}"   # "A.12" -> "A"
  if [[ "$group" != "$last_section" ]]; then echo ""; echo "─── Section $group ───"; last_section="$group"; fi
  total=$((total+1))
  mark="✗"
  [ "$pass" = "1" ] && { mark="✓"; passed=$((passed+1)); } || {
    case "$sev" in P0) p0_fail=$((p0_fail+1)) ;; P1) p1_fail=$((p1_fail+1)) ;; P2) p2_fail=$((p2_fail+1)) ;; esac
  }
  notetag=""; [ -n "$note" ] && notetag="  ($note)"
  printf "  %s [%s] %s%s\n" "$mark" "$sev" "$item" "$notetag"
done

echo ""
echo "─── Summary ───"
pct=$((100 * passed / total))
echo "  passed: $passed/$total ($pct%)"
[ "$p0_fail" -gt 0 ] && echo "  P0 fails (blockers): $p0_fail"
[ "$p1_fail" -gt 0 ] && echo "  P1 fails (hygiene):  $p1_fail"
[ "$p2_fail" -gt 0 ] && echo "  P2 fails (polish):   $p2_fail"

echo ""
if [ "$p0_fail" -gt 0 ]; then
  echo "✗ Launch is BLOCKED. Fix P0 items before deploying."
  exit 1
else
  echo "✓ All P0 checks passed. Ready to ship."
  exit 0
fi
