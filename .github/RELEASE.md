# Release Process

This document describes how to create a new release of Ziglog.

## Automated Release (Recommended)

Releases are automatically built and published when you push a tag:

```bash
# Update version in relevant files (CHANGELOG.md, etc.)
git add .
git commit -m "chore: prepare release v0.1.0"

# Create and push tag
git tag v0.1.0
git push origin v0.1.0
```

This will:
1. Trigger the release workflow
2. Build binaries for all platforms (Linux, macOS, Windows × x86_64, ARM64)
3. Run tests on native platforms
4. Create a GitHub release with artifacts
5. Generate release notes automatically

## Manual Release

To manually trigger a release:

1. Go to **Actions** → **Release** workflow
2. Click **Run workflow**
3. Enter the tag name (e.g., `v0.1.0`)
4. Click **Run workflow**

## Supported Platforms

The release workflow builds for:

- **Linux**
  - x86_64 (Intel/AMD)
  - aarch64 (ARM64)

- **macOS**
  - x86_64 (Intel)
  - aarch64 (Apple Silicon)

- **Windows**
  - x86_64 (Intel/AMD)
  - aarch64 (ARM64)

## Artifact Format

Each platform artifact is a `.tar.gz` containing:
- `ziglog` or `ziglog.exe` - The executable
- `README.md` - Documentation
- `LICENSE` - License file

## Version Numbering

Ziglog follows [Semantic Versioning](https://semver.org/):

- **MAJOR** version: Incompatible API changes
- **MINOR** version: New functionality (backward compatible)
- **PATCH** version: Bug fixes (backward compatible)

Examples:
- `v0.1.0` - Initial release
- `v0.2.0` - New features added
- `v0.2.1` - Bug fixes
- `v1.0.0` - First stable release

## Pre-release Process

1. **Update CHANGELOG.md** with all changes since last release
2. **Run full test suite**: `zig build test-all`
3. **Test build locally**: `zig build -Doptimize=ReleaseSafe`
4. **Review documentation** for accuracy
5. **Create tag and push**

## Post-release

After a successful release:

1. Verify artifacts are available on the [Releases](https://github.com/nikolay/ziglog/releases) page
2. Test download and extraction on at least one platform
3. Update documentation if needed
4. Announce release (if applicable)

## Troubleshooting

### Build fails on specific platform

- Check the workflow logs in GitHub Actions
- Cross-compilation issues: Ensure Zig target is correct
- Test locally with: `zig build -Dtarget=<target-triple>`

### Release not created

- Ensure tag matches pattern `v*` (e.g., `v0.1.0`)
- Check workflow permissions in repository settings
- Verify `GITHUB_TOKEN` has write access

### Artifacts missing

- Check if all build jobs completed successfully
- Review upload-artifact steps in workflow logs
- Ensure artifact retention period hasn't expired (default: 7 days)

## Manual Build Commands

To manually build for a specific platform:

```bash
# Linux x86_64
zig build -Doptimize=ReleaseSafe -Dtarget=x86_64-linux-gnu

# Linux ARM64
zig build -Doptimize=ReleaseSafe -Dtarget=aarch64-linux-gnu

# macOS Intel
zig build -Doptimize=ReleaseSafe -Dtarget=x86_64-macos

# macOS Apple Silicon
zig build -Doptimize=ReleaseSafe -Dtarget=aarch64-macos

# Windows x86_64
zig build -Doptimize=ReleaseSafe -Dtarget=x86_64-windows-gnu

# Windows ARM64
zig build -Doptimize=ReleaseSafe -Dtarget=aarch64-windows-gnu
```
