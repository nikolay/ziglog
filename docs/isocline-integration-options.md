# Isocline Integration Options

## Current Situation

Ziglog has **internalized** the isocline library (v1.0.4) from https://github.com/daanx/isocline:

- 32 C source files in `src/isocline/`
- MIT-licensed pure C library
- Built as a single compilation unit (`isocline.c` includes all other files)
- Modified files: `common.h`, `completers.c`, `completions.c`, `env.h`, `history.c`, `isocline.c`, `undo.c`

**Note**: Documentation still incorrectly mentions "replxx" - this should be updated to "isocline".

---

## Option 1: Git Submodule

### Pros
✅ **Official upstream tracking**: Always know which version you're using
✅ **Easy updates**: `git submodule update --remote` pulls latest
✅ **Clear provenance**: Explicit link to upstream repository
✅ **Smaller repo size**: Submodule doesn't bloat main repo
✅ **Standard practice**: Git submodules are well-understood

### Cons
❌ **Harder for contributors**: Must run `git submodule init && git submodule update`
❌ **Customization complexity**: Local patches require fork or workarounds
❌ **Build complexity**: Need to point to submodule path in build.zig
❌ **CI/CD friction**: Need `--recursive` flag or manual initialization
❌ **Lost modifications**: Current customizations would need to be re-applied
❌ **Detached HEAD**: Submodules often in detached state, confusing workflow

### Implementation Steps
```bash
# Remove internalized version
rm -rf src/isocline

# Add as submodule
git submodule add https://github.com/daanx/isocline.git vendor/isocline

# Update build.zig to point to vendor/isocline/src/isocline.c
# Update include path to vendor/isocline/src

# For future updates
git submodule update --remote vendor/isocline
```

---

## Option 2: Vendoring with Update Script (Recommended)

### Pros
✅ **Simple for users**: No submodule initialization needed
✅ **Offline builds**: All code in repository
✅ **Easy customization**: Modify files directly, track in git
✅ **No workflow changes**: Regular git operations work normally
✅ **Selective updates**: Review upstream changes before merging
✅ **Patch tracking**: Can maintain local modifications clearly

### Cons
❌ **Manual updates**: Need to run script to pull upstream
❌ **Larger repo**: Full source code checked in
❌ **Merge conflicts**: Updates may conflict with local changes
❌ **Version drift**: Easy to forget to update

### Implementation: Automated Update Script

Create `scripts/update-isocline.sh`:

```bash
#!/bin/bash
set -euo pipefail

# Configuration
UPSTREAM_REPO="https://github.com/daanx/isocline.git"
UPSTREAM_BRANCH="main"
VENDOR_DIR="src/isocline"
TEMP_DIR=$(mktemp -d)

echo "==> Updating isocline from upstream..."

# Clone upstream to temp directory
git clone --depth=1 --branch="$UPSTREAM_BRANCH" "$UPSTREAM_REPO" "$TEMP_DIR"

# Get current and new versions
CURRENT_VERSION=$(grep "define IC_VERSION" "$VENDOR_DIR/isocline.h" | awk '{print $3}')
NEW_VERSION=$(grep "define IC_VERSION" "$TEMP_DIR/src/isocline.h" | awk '{print $3}')

echo "Current version: $CURRENT_VERSION"
echo "New version: $NEW_VERSION"

if [ "$CURRENT_VERSION" = "$NEW_VERSION" ]; then
    echo "Already up to date!"
    rm -rf "$TEMP_DIR"
    exit 0
fi

# Backup current version
BACKUP_DIR="$VENDOR_DIR.backup.$(date +%Y%m%d_%H%M%S)"
cp -r "$VENDOR_DIR" "$BACKUP_DIR"
echo "Backed up current version to: $BACKUP_DIR"

# Copy new files
echo "==> Copying upstream files..."
rm -rf "$VENDOR_DIR"/*
cp -r "$TEMP_DIR/src/"* "$VENDOR_DIR/"

# Clean up
rm -rf "$TEMP_DIR"

echo ""
echo "==> Update complete!"
echo "Next steps:"
echo "  1. Review changes: git diff $VENDOR_DIR"
echo "  2. Re-apply any local customizations from: $BACKUP_DIR"
echo "  3. Test the build: zig build test-all"
echo "  4. Commit: git add $VENDOR_DIR && git commit -m 'Update isocline to version $NEW_VERSION'"
echo ""
echo "To rollback: cp -r $BACKUP_DIR/* $VENDOR_DIR/"
```

---

## Option 3: Hybrid - Automated Merge with Patch Files

### Pros
✅ **Best of both worlds**: Track upstream + maintain customizations
✅ **Reproducible**: Patches are version-controlled
✅ **Transparent**: Clear what's changed from upstream
✅ **Automated**: Script handles merging patches

### Cons
❌ **Complexity**: Requires patch management workflow
❌ **Maintenance burden**: Patches may break on upstream updates
❌ **Learning curve**: Team needs to understand patch workflow

### Implementation

Create `scripts/update-isocline-with-patches.sh`:

```bash
#!/bin/bash
set -euo pipefail

UPSTREAM_REPO="https://github.com/daanx/isocline.git"
UPSTREAM_BRANCH="main"
VENDOR_DIR="src/isocline"
PATCHES_DIR="patches/isocline"
TEMP_DIR=$(mktemp -d)

echo "==> Cloning upstream isocline..."
git clone --depth=1 --branch="$UPSTREAM_BRANCH" "$UPSTREAM_REPO" "$TEMP_DIR"

# Apply patches
if [ -d "$PATCHES_DIR" ]; then
    echo "==> Applying local patches..."
    for patch in "$PATCHES_DIR"/*.patch; do
        if [ -f "$patch" ]; then
            echo "  Applying: $(basename "$patch")"
            if ! (cd "$TEMP_DIR/src" && patch -p1 < "$(pwd)/$patch"); then
                echo "ERROR: Patch failed: $patch"
                echo "Manual resolution required!"
                exit 1
            fi
        fi
    done
fi

# Replace vendored code
echo "==> Updating vendored code..."
rm -rf "$VENDOR_DIR"/*
cp -r "$TEMP_DIR/src/"* "$VENDOR_DIR/"

# Clean up
rm -rf "$TEMP_DIR"

echo "==> Update complete! Run: zig build test-all"
```

Create patches from current modifications:
```bash
# Generate patches for local changes
cd src/isocline
for file in common.h completers.c completions.c env.h history.c isocline.c undo.c; do
    git diff HEAD -- "$file" > "../../patches/isocline/$file.patch"
done
```

---

## Recommendation

**Use Option 2: Vendoring with Update Script**

### Rationale

1. **Isocline is stable**: v1.0.4 released, infrequent breaking changes expected
2. **Local modifications exist**: You've already customized 7 files
3. **Simple workflow**: No submodule complexity for contributors
4. **Zig ecosystem norm**: Most Zig projects vendor C dependencies
5. **Selective updates**: You can review and test upstream changes before merging

### Implementation Plan

1. Create `scripts/update-isocline.sh` (see script above)
2. Make it executable: `chmod +x scripts/update-isocline.sh`
3. Document in README.md under "Updating Dependencies"
4. Add to `.gitignore`: `src/isocline.backup.*`
5. **Fix documentation**: Replace all "replxx" references with "isocline"

### When to Run Updates

- **Quarterly**: Check for upstream improvements (low urgency)
- **Bug reports**: If users report isocline-related issues
- **Security advisories**: Immediately (though rare for this library)
- **Feature needs**: When upstream adds needed functionality

---

## Migration Checklist

If switching to submodule (Option 1):

- [ ] Remove `src/isocline/` from git tracking
- [ ] Add submodule: `git submodule add ...`
- [ ] Update `build.zig` paths
- [ ] Update `.gitmodules`
- [ ] Update CI/CD to initialize submodules
- [ ] Document in README: submodule initialization steps
- [ ] Re-apply local patches as a fork or patch set

If implementing update script (Option 2):

- [x] Keep current `src/isocline/` structure
- [ ] Create `scripts/update-isocline.sh`
- [ ] Test script in dry-run
- [ ] Document usage in README.md
- [ ] Add backup dirs to `.gitignore`
- [ ] **Fix replxx → isocline in all documentation**

---

## Additional Considerations

### Tracking Upstream Version

Add to `src/isocline/UPSTREAM_VERSION`:
```
Isocline version: 1.0.4
Upstream: https://github.com/daanx/isocline
Commit: <commit-hash>
Last updated: 2024-11-20

Local modifications:
- common.h: Custom memory allocator integration
- completers.c: Ziglog-specific completions
- completions.c: REPL command completion
- env.h: Environment variable handling
- history.c: History file format
- isocline.c: Integration glue
- undo.c: Undo/redo behavior
```

### Testing After Updates

```bash
# Full test suite
zig build test-all

# Manual REPL testing
./zig-out/bin/ziglog
> [Test syntax highlighting]
> [Test tab completion]
> [Test history with Up/Down]
> [Test multi-line editing]
```

---

## Conclusion

For ziglog, **vendoring with an update script** strikes the best balance:
- Maintains your local customizations
- Enables upstream tracking when needed
- Keeps build process simple
- Standard practice in Zig ecosystem

The script automates 90% of the update work while giving you control over the remaining 10% that needs human review.
