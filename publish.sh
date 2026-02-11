#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# Publish all packages to NPM under the @sownt scope
#
# Usage:
#   ./publish.sh              # publish using versions from package.json
#   ./publish.sh 1.0.0        # override version for all packages
#   ./publish.sh --dry-run    # preview what would be published
#   ./publish.sh 1.0.0 --dry-run
# ─────────────────────────────────────────────────────────────

VERSION=""
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    *)         VERSION="$arg" ;;
  esac
done

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGES_DIR="$ROOT_DIR/packages"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log()   { echo -e "${CYAN}[publish]${NC} $*"; }
ok()    { echo -e "${GREEN}  ✔${NC} $*"; }
warn()  { echo -e "${YELLOW}  ⚠${NC} $*"; }
error() { echo -e "${RED}  ✘${NC} $*"; }

# ── Pre-flight checks ───────────────────────────────────────
if ! command -v npm &>/dev/null; then
  error "npm is not installed"; exit 1
fi

if ! npm whoami &>/dev/null; then
  error "Not logged in to npm. Run 'npm login' first."; exit 1
fi

NPM_USER=$(npm whoami)
log "Logged in as ${GREEN}${NPM_USER}${NC}"

# ── Install dependencies ────────────────────────────────────
log "Installing dependencies..."
cd "$ROOT_DIR"
npm ci --silent

# ── Build all packages ──────────────────────────────────────
log "Building all packages..."
npm run build --workspaces

# ── Publish each package ────────────────────────────────────
PUBLISHED=()
SKIPPED=()
FAILED=()

for pkg_dir in "$PACKAGES_DIR"/*/; do
  pkg_json="$pkg_dir/package.json"
  [[ ! -f "$pkg_json" ]] && continue

  # Skip private packages
  if grep -q '"private":\s*true' "$pkg_json" 2>/dev/null; then
    pkg_name=$(grep '"name":' "$pkg_json" | sed 's/.*"name": "\(.*\)".*/\1/')
    warn "Skipping private package: $pkg_name"
    SKIPPED+=("$pkg_name")
    continue
  fi

  # Rename scope: @usewaypoint → @sownt
  sed -i.bak 's|"@usewaypoint/|"@sownt/|g' "$pkg_json"
  rm -f "$pkg_json.bak"

  # Override version if provided
  if [[ -n "$VERSION" ]]; then
    sed -i.bak "s|\"version\": \"[^\"]*\"|\"version\": \"$VERSION\"|" "$pkg_json"
    rm -f "$pkg_json.bak"
  fi

  pkg_name=$(grep '"name":' "$pkg_json" | sed 's/.*"name": "\(.*\)".*/\1/')
  pkg_version=$(grep '"version":' "$pkg_json" | sed 's/.*"version": "\(.*\)".*/\1/')

  log "Publishing ${CYAN}${pkg_name}@${pkg_version}${NC} ..."

  cd "$pkg_dir"

  PUBLISH_ARGS=(--access public)
  if $DRY_RUN; then
    PUBLISH_ARGS+=(--dry-run)
  fi

  if npm publish "${PUBLISH_ARGS[@]}"; then
    ok "$pkg_name@$pkg_version"
    PUBLISHED+=("$pkg_name@$pkg_version")
  else
    error "Failed to publish $pkg_name@$pkg_version"
    FAILED+=("$pkg_name@$pkg_version")
  fi

  cd "$ROOT_DIR"
done

# ── Revert scope changes (restore git state) ────────────────
log "Reverting package.json changes..."
git checkout -- packages/

# ── Summary ─────────────────────────────────────────────────
echo ""
log "━━━━━━━━━━━━━━━━ Summary ━━━━━━━━━━━━━━━━"
if $DRY_RUN; then
  warn "DRY RUN — nothing was actually published"
fi

if [[ ${#PUBLISHED[@]} -gt 0 ]]; then
  ok "Published (${#PUBLISHED[@]}):"
  for p in "${PUBLISHED[@]}"; do echo "      $p"; done
fi

if [[ ${#SKIPPED[@]} -gt 0 ]]; then
  warn "Skipped (${#SKIPPED[@]}):"
  for p in "${SKIPPED[@]}"; do echo "      $p"; done
fi

if [[ ${#FAILED[@]} -gt 0 ]]; then
  error "Failed (${#FAILED[@]}):"
  for p in "${FAILED[@]}"; do echo "      $p"; done
  exit 1
fi

echo ""
ok "Done!"
