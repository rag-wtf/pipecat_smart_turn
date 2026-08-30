#!/usr/bin/env bash
#
# Publishes all packages of the pipecat_smart_turn federated plugin to
# pub.dev in dependency order (keyless OIDC -- no credentials required).
#
# Design notes:
#   * The repository keeps `path:` dependencies between sibling packages so
#     that local development and per-package CI work without a workspace.
#     `dart pub publish` rejects path dependencies, so each package is
#     copied to a temporary directory and its pubspec is rewritten by
#     scripts/rewrite_pubspecs.py before being published.
#   * A single semver tag (e.g. `v0.1.0+1`) authorizes publishing every
#     package whose version matches the tag (pub.dev admin config per
#     package: tag pattern `v{{version}}`). Packages whose version does not
#     match the tag are skipped.
#   * The pub.dev `publisher` (rag.wtf) is assigned on pub.dev -- it is not
#     a pubspec key (pub rejects `publisher:` as unknown).
#   * Publish order is topological: the platform interface first, then the
#     platform implementations, then the app-facing package last.
#
# Usage:
#   PUBLISH_DRY_RUN=1 scripts/publish_packages.sh   # validation only
#   scripts/publish_packages.sh                     # real publish (tag push)
#
# Environment:
#   PUBLISH_DRY_RUN   When non-empty, runs `dart pub publish --dry-run`
#                     and never uploads anything.
#   PUBLISH_TAG_VERSION  Package version authorized by the pushed tag
#                     (defaults to the `v*` tag derived from GITHUB_REF).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

PUBLISH_DRY_RUN="${PUBLISH_DRY_RUN:-}"
PUBLISH_TAG_VERSION="${PUBLISH_TAG_VERSION:-}"

# Dependency order: platform interface -> implementations -> app package.
ORDER=(
  pipecat_smart_turn_platform_interface
  pipecat_smart_turn_android
  pipecat_smart_turn_ios
  pipecat_smart_turn_linux
  pipecat_smart_turn_macos
  pipecat_smart_turn_web
  pipecat_smart_turn_windows
  pipecat_smart_turn
)

# Derive the authorized version from the tag ref (e.g. refs/tags/v0.1.0+1).
if [[ -z "$PUBLISH_TAG_VERSION" && -n "${GITHUB_REF:-}" ]]; then
  case "$GITHUB_REF" in
  refs/tags/v*) PUBLISH_TAG_VERSION="${GITHUB_REF#refs/tags/v}" ;;
  *) echo "::warning::Not a v* tag ref ($GITHUB_REF); publishing all packages" ;;
  esac
fi

echo "==> Preparing publish copies in $WORK_DIR"
for pkg in "${ORDER[@]}"; do
  rsync -a \
    --exclude "build" \
    --exclude ".dart_tool" \
    --exclude "coverage" \
    --exclude "*.log" \
    "$ROOT/$pkg/" "$WORK_DIR/$pkg/"
done

echo "==> Rewriting pubspecs for publishing"
python3 "$SCRIPT_DIR/rewrite_pubspecs.py" "$WORK_DIR"

if [[ -n "$PUBLISH_DRY_RUN" ]]; then
  echo "==> DRY RUN: validating every package without uploading (PUBLISH_DRY_RUN=1)"
fi

published=0
skipped=0
for pkg in "${ORDER[@]}"; do
  version="$(sed -n 's/^version: //p' "$ROOT/$pkg/pubspec.yaml" | head -n 1 | tr -d '[:space:]')"
  if [[ -z "$version" ]]; then
    echo "::error::Could not determine version of $pkg"
    exit 1
  fi

  if [[ -z "$PUBLISH_DRY_RUN" && -n "$PUBLISH_TAG_VERSION" && "$version" != "$PUBLISH_TAG_VERSION" ]]; then
    echo "::warning::Skipping $pkg: version $version does not match tag version $PUBLISH_TAG_VERSION"
    skipped=$((skipped + 1))
    continue
  fi

  echo "==> Publishing $pkg $version ($([[ -n "$PUBLISH_DRY_RUN" ]] && echo dry-run || echo live))"

  attempts=4
  ok=false
  for i in $(seq 1 "$attempts"); do
    if (cd "$WORK_DIR/$pkg" && dart pub publish "$([[ -n "$PUBLISH_DRY_RUN" ]] && echo --dry-run || echo --force)"); then
      ok=true
      break
    fi
    if [[ -n "$PUBLISH_DRY_RUN" ]]; then
      break
    fi
    echo "    Attempt $i/$attempts failed; pub.dev ingest can lag. Retrying in 20s..."
    sleep 20
  done

  if [[ "$ok" != true ]]; then
    echo "::error::Failed to publish $pkg $version"
    exit 1
  fi
  published=$((published + 1))
done

echo "==> Done: $published published, $skipped skipped (tag filter), in $WORK_DIR"
if [[ -n "$PUBLISH_DRY_RUN" ]]; then
  echo "(dry run -- nothing was uploaded)"
fi