#!/bin/bash
# Update isocline library from upstream
# Usage: ./scripts/update-isocline.sh [--dry-run]

set -euo pipefail

# Configuration
UPSTREAM_REPO="https://github.com/daanx/isocline.git"
UPSTREAM_BRANCH="main"
VENDOR_DIR="src/isocline"
TEMP_DIR=$(mktemp -d)
DRY_RUN=false

# Parse arguments
if [ "${1:-}" = "--dry-run" ]; then
    DRY_RUN=true
    echo "==> DRY RUN MODE - No changes will be made"
    echo ""
fi

# Trap to clean up temp dir
trap 'rm -rf "$TEMP_DIR"' EXIT

echo "==> Updating isocline from upstream..."
echo "    Repository: $UPSTREAM_REPO"
echo "    Branch: $UPSTREAM_BRANCH"
echo ""

# Clone upstream to temp directory
echo "==> Cloning upstream repository..."
git clone --quiet --depth=1 --branch="$UPSTREAM_BRANCH" "$UPSTREAM_REPO" "$TEMP_DIR"

# Get current and new versions
if [ -f "$VENDOR_DIR/isocline.h" ]; then
    CURRENT_VERSION=$(grep "#define IC_VERSION" "$VENDOR_DIR/isocline.h" | awk '{print $3}' | tr -d '()')
else
    CURRENT_VERSION="unknown"
fi

NEW_VERSION=$(grep "#define IC_VERSION" "$TEMP_DIR/include/isocline.h" | awk '{print $3}' | tr -d '()')

echo "==> Version Information:"
echo "    Current version: $CURRENT_VERSION"
echo "    New version: $NEW_VERSION"
echo ""

if [ "$CURRENT_VERSION" = "$NEW_VERSION" ]; then
    echo "✓ Already up to date!"
    exit 0
fi

# Get commit info
cd "$TEMP_DIR"
COMMIT_HASH=$(git rev-parse --short HEAD)
COMMIT_DATE=$(git log -1 --format=%ci)
COMMIT_MSG=$(git log -1 --format=%s)
cd - > /dev/null

echo "==> Upstream commit information:"
echo "    Hash: $COMMIT_HASH"
echo "    Date: $COMMIT_DATE"
echo "    Message: $COMMIT_MSG"
echo ""

if [ "$DRY_RUN" = true ]; then
    echo "==> Would update from version $CURRENT_VERSION to $NEW_VERSION"
    echo "==> Dry run complete. Run without --dry-run to apply changes."
    exit 0
fi

# Backup current version
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$VENDOR_DIR.backup.$TIMESTAMP"
echo "==> Creating backup..."
cp -r "$VENDOR_DIR" "$BACKUP_DIR"
echo "    Backed up to: $BACKUP_DIR"
echo ""

# Show what files were modified locally (if in git repo)
if git rev-parse --git-dir > /dev/null 2>&1; then
    echo "==> Local modifications (if any):"
    if git diff --quiet HEAD -- "$VENDOR_DIR" 2>/dev/null; then
        echo "    No uncommitted local modifications"
    else
        echo "    WARNING: You have uncommitted changes in $VENDOR_DIR"
        git diff --stat HEAD -- "$VENDOR_DIR" || true
    fi
    echo ""
fi

# Copy new files
echo "==> Copying upstream files..."
rm -rf "${VENDOR_DIR:?}"/*
cp -r "$TEMP_DIR/src/"* "$VENDOR_DIR/"
cp "$TEMP_DIR/include/isocline.h" "$VENDOR_DIR/"

# Count files
FILE_COUNT=$(find "$VENDOR_DIR" -type f | wc -l | tr -d ' ')
echo "    Copied $FILE_COUNT files"
echo ""

# Create/update upstream version tracking file
cat > "$VENDOR_DIR/UPSTREAM_VERSION" << EOF
Isocline version: $NEW_VERSION
Upstream: $UPSTREAM_REPO
Commit: $COMMIT_HASH
Date: $COMMIT_DATE
Last updated: $(date +%Y-%m-%d)

Update script: scripts/update-isocline.sh
Backup: $BACKUP_DIR

Commit message: $COMMIT_MSG

Local modifications:
- Review git diff to see what needs to be re-applied
EOF

echo "==> Update complete!"
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║ NEXT STEPS                                                    ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  1. Review changes:"
echo "     git diff $VENDOR_DIR"
echo ""
echo "  2. Check for local modifications that need re-applying:"
echo "     diff -r $BACKUP_DIR $VENDOR_DIR"
echo ""
echo "  3. Test the build:"
echo "     zig build test-all"
echo ""
echo "  4. Test the REPL interactively:"
echo "     zig build run"
echo ""
echo "  5. If everything works, commit:"
echo "     git add $VENDOR_DIR"
echo "     git commit -m 'Update isocline to version $NEW_VERSION'"
echo ""
echo "  6. If issues occur, rollback:"
echo "     rm -rf $VENDOR_DIR"
echo "     cp -r $BACKUP_DIR $VENDOR_DIR"
echo ""
echo "═══════════════════════════════════════════════════════════════"
