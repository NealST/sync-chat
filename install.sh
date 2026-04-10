#!/bin/bash
# install.sh — install sync-chat hook files into a project directory
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/sync-chat/main/install.sh)
#   bash <(curl -fsSL ...) --force          # overwrite existing files
#   bash <(curl -fsSL ...) ./my-project     # install into a specific directory

set -euo pipefail

REPO="https://raw.githubusercontent.com/YOUR_USERNAME/sync-chat/main/templates"

FILES=(
  ".github/hooks/sync-chat.json"
  ".cursor/hooks.json"
  "scripts/export.sh"
  "scripts/restore.sh"
)

# ── Parse arguments ────────────────────────────────────────────────────────────

FORCE=0
TARGET=""

for arg in "$@"; do
  case "$arg" in
    --force|-f) FORCE=1 ;;
    --help|-h)
      echo "Usage: bash install.sh [target-dir] [--force]"
      echo ""
      echo "  target-dir   Directory to install into (default: current directory)"
      echo "  --force, -f  Overwrite files that already exist"
      exit 0
      ;;
    *) TARGET="$arg" ;;
  esac
done

TARGET="${TARGET:-.}"

if [ ! -d "$TARGET" ]; then
  echo "Error: target directory does not exist: $TARGET"
  exit 1
fi

TARGET=$(cd "$TARGET" && pwd)

# ── Detect download tool ───────────────────────────────────────────────────────

if command -v curl &>/dev/null; then
  download() { curl -fsSL "$1"; }
elif command -v wget &>/dev/null; then
  download() { wget -qO- "$1"; }
else
  echo "Error: curl or wget is required."
  exit 1
fi

# ── Install files ──────────────────────────────────────────────────────────────

echo ""
echo "Installing sync-chat into $TARGET"
echo ""

INSTALLED=0
SKIPPED=0

for rel in "${FILES[@]}"; do
  dest="$TARGET/$rel"
  dir="$(dirname "$dest")"

  if [ -f "$dest" ] && [ "$FORCE" = "0" ]; then
    echo "  skip   $rel  (already exists, use --force to overwrite)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  mkdir -p "$dir"

  # Download to a temp file first; only replace dest if download succeeds.
  # This prevents leaving an empty file behind on network/404 errors.
  tmp=$(mktemp)
  if ! download "$REPO/$rel" > "$tmp"; then
    rm -f "$tmp"
    echo "  error  $rel  (download failed)"
    exit 1
  fi
  mv "$tmp" "$dest"

  if [[ "$rel" == *.sh ]]; then
    chmod +x "$dest"
  fi

  echo "  write  $rel"
  INSTALLED=$((INSTALLED + 1))
done

echo ""

if [ "$INSTALLED" = "0" ] && [ "$SKIPPED" -gt 0 ]; then
  echo "All files already exist. Run with --force to overwrite."
  echo ""
else
  echo "Done! $INSTALLED file(s) installed."
  echo ""
  echo "Next steps:"
  echo "  1. git add .github/hooks/ .cursor/hooks.json scripts/"
  echo "  2. git commit -m \"chore: add sync-chat hooks\""
  echo "  3. git push"
  echo ""
fi
