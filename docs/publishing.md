# Publishing to pub.dev

`pipecat_smart_turn` is a **federated plugin**: `pipecat_smart_turn` (app-facing)
plus seven support packages (`pipecat_smart_turn_platform_interface` and the six
platform implementations) are hosted on pub.dev as **independent packages**.

Publishing is automated end-to-end with GitHub Actions using **keyless OIDC**:
pub.dev verifies the pushed `v*` tag against each package's admin
configuration. **No secrets are stored in the repository.**

## Architecture

| Piece | Location | Purpose |
| --- | --- | --- |
| Workflow | `.github/workflows/publish.yml` | `validate` job on PRs and tags; `publish` job on `v*` tags |
| Publish script | `scripts/publish_packages.sh` | Publishes packages topologically (interface → implementations → app package) |
| Pubspec rewrite | `scripts/rewrite_pubspecs.py` | Turns dev `path:` deps into hosted constraints in disposable publish copies |

### Why a rewrite script instead of melos?

The repository deliberately uses `path:` dependencies between sibling packages
so that local development (`setup.sh`) and the per-package CI workflows work
without a monorepo tool. `dart pub publish` rejects path dependencies, so the
pipeline copies each package and rewrites the pubspec before publishing:

* `publish_to: none` is removed.
* An `environment.flutter` constraint is added (required for plugins).
* A `homepage` / `repository` is added for packages that lack one.
* Sibling deps become hosted caret constraints (`^0.1.0`).
* A `dependency_overrides` section points back at the local copies; pub
  **strips** overrides from the uploaded pubspec
  (`stripDependencyOverrides` in the pub tool), so the published artifact
  contains only clean hosted constraints.

The dependency graph is static and small, so a fixed publish order replaces a
melos workspace: platform interface first, then the six platform
implementations, then `pipecat_smart_turn` last.

> `publisher` is **not** a pubspec key — `dart pub publish` rejects it
> ("'publisher' is not a key recognized by pub"). A package's publisher on
> pub.dev is assigned through the pub.dev admin, not the pubspec.

## One-time setup (manual, required)

> ⚠️ These steps cannot be automated. Until they are done, the `publish` job
> will be rejected by pub.dev.

### 1. Claim the `rag.wtf` publisher

All eight packages must be published under the [`rag.wtf`](https://pub.dev/publishers/rag.wtf)
publisher. The publisher is a pub.dev **account-level** entity tied to the
verified domain — it is not a pubspec field.

1. Go to <https://pub.dev/publish> and create the `rag.wtf` publisher.
2. Verify you control the domain (DNS record or verification file hosted at
   `https://rag.wtf/.well-known/...`).
3. Add the GitHub account used for publishing as a **member** of the
   publisher, so its uploads are owned by `rag.wtf`.

### 2. Enable automated publishing per package

Repeat for **each of the 8 packages**:

1. Open the package's **Admin** tab on pub.dev (e.g.
   `https://pub.dev/packages/pipecat_smart_turn_platform_interface/admin`).
2. Find **Automated publishing** → **Enable publishing from GitHub Actions**.
3. Repository: `rag-wtf/pipecat_smart_turn`.
4. Tag pattern: `v{{version}}`.
5. (Recommended) Check **Require GitHub Actions environment** and name it
   `pub.dev` — this matches the `environment: pub.dev` block in
   `.github/workflows/publish.yml` and lets you add required reviewers as a
   release gate.

Packages:

- `pipecat_smart_turn`
- `pipecat_smart_turn_platform_interface`
- `pipecat_smart_turn_android`
- `pipecat_smart_turn_ios`
- `pipecat_smart_turn_linux`
- `pipecat_smart_turn_macos`
- `pipecat_smart_turn_web`
- `pipecat_smart_turn_windows`

## Releasing a new version

A **single tag** releases every package whose version matches the tag.

1. Bump `version:` in the `pubspec.yaml` of the packages you want to release
   (typically all eight, kept in lockstep) and update each package's
   `CHANGELOG.md`.
2. Commit and push to `main`.
3. Tag and push — the `v{{version}}` pattern means the tag **must** equal the
   package version:

   ```bash
   git tag v0.1.0+1
   git push origin v0.1.0+1
   ```

   > Note: `git tag v0.1.0+1` needs a refspec/quoting hint on some shells
   > because of the `+`. `git push origin v0.1.0+1` is unambiguous.
4. The `publish` workflow runs `validate` (analyze, test, dry-run) and then
   `publish` in topological order. Packages whose version does **not** match
   the tag are skipped with a warning.

### Partial releases

If only some packages bumped their version, only those matching the tag are
published. Keep the platform interface published before any package that
depends on it — the script handles the order, but the interface must have
moved to the new version first if its API changed.

## Verifying locally

```bash
# Runs every package through `dart pub publish --dry-run` (no upload):
PUBLISH_DRY_RUN=1 scripts/publish_packages.sh
```