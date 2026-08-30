#!/usr/bin/env python3
"""Rewrite package pubspecs for publishing.

The repository keeps inter-package dependencies as `path:` dependencies so
that local development and the existing CI workflows work out of the box.
`dart pub publish` rejects path dependencies in `dependencies:`, so before
publishing we prepare a disposable copy of each package whose pubspec has:

  * `publish_to: none` removed (packages are hosted on pub.dev).
  * An explicit `environment.flutter` constraint (required for plugins).
  * A `homepage` / `repository` pointing at the project.
  * Sibling `path:` dependencies rewritten to hosted caret constraints.
  * A `dependency_overrides` section pointing back at the sibling packages.

The overrides are only used to resolve dependencies during `pub get` --
`dart pub publish` strips `dependency_overrides` from the uploaded
pubspec (see pubspec_utils.dart: stripDependencyOverrides), so the
published artifact contains plain hosted constraints.

Note: the pub.dev `publisher` (rag.wtf) is NOT a pubspec key -- pub rejects
`publisher:` as an unknown key. The publisher is assigned per package on
pub.dev (see docs/publishing.md).

Usage: rewrite_pubspecs.py <work_dir> [flutter_version]

The work_dir must contain the checked out sibling packages.
"""

import pathlib
import re
import sys

REPO_URL = "https://github.com/rag-wtf/pipecat_smart_turn"
PATH_DEP_RE = re.compile(
    r"^(?P<indent> {2})(?P<name>pipecat_smart_turn(?:_\w+)?):\n {4}path: \.\./(?P=name)\n",
    re.MULTILINE,
)

PUBLISH_TO_RE = re.compile(r"^publish_to:.*\n", re.MULTILINE)
ENV_BLOCK_RE = re.compile(r"^environment:\n(?: {2,}[^\n]*\n?)*", re.MULTILINE)


def strip_build_metadata(version: str) -> str:
    """'0.1.0+1' -> '0.1.0' (build metadata is ignored by caret constraints)."""
    return re.match(r"^\d+\.\d+\.\d+", version).group(0)


def main() -> int:
    work_dir = pathlib.Path(sys.argv[1]).resolve()
    flutter_constraint = sys.argv[2] if len(sys.argv) > 2 else ">=3.29.0"

    # Map of sibling name -> version, read from the working copies.
    sibling_versions = {}
    for pubspec in work_dir.glob("pipecat_smart_turn*/pubspec.yaml"):
        name = pubspec.parent.name
        version = re.search(r"^version: (.+)$", pubspec.read_text(), re.MULTILINE)
        if version:
            sibling_versions[name] = version.group(1)

    for pubspec in sorted(work_dir.glob("pipecat_smart_turn*/pubspec.yaml")):
        name = pubspec.parent.name
        text = pubspec.read_text()

        # Remove publish_to (nothing here is blocked from publishing).
        text = PUBLISH_TO_RE.sub("", text)

        # Ensure an explicit Flutter SDK floor for plugin validation.
        # (Only looks inside the `environment:` block so the `flutter:
        #  sdk: flutter` dependency is not mistaken for the constraint.)
        def ensure_env_flutter(match: re.Match) -> str:
            block = match.group(0)
            if re.search(r"^ {2}flutter:", block, re.MULTILINE):
                return block
            return f"{block.rstrip()}\n  flutter: \"{flutter_constraint}\"\n"

        text = ENV_BLOCK_RE.sub(ensure_env_flutter, text, count=1)

        # Add homepage/repository shown on pub.dev for the published package.
        if not re.search(r"^homepage:", text, re.MULTILINE):
            text = re.sub(
                r"^(version: .*)$",
                lambda m: f"{m.group(1)}\nhomepage: {REPO_URL}\nrepository: {REPO_URL}",
                text,
                count=1,
                flags=re.MULTILINE,
            )

        # Rewrite sibling path dependencies to hosted caret constraints and
        # collect the ones that need a dependency override.
        override_names = []

        def rewrite_path_dep(match: re.Match) -> str:
            dep_name = match.group("name")
            version = sibling_versions.get(dep_name)
            if version is None:
                raise SystemExit(f"Unknown sibling {dep_name!r} in {name} pubspec")
            override_names.append(dep_name)
            constraint = f"^{strip_build_metadata(version)}"
            return f"{match.group('indent')}{dep_name}: {constraint}\n"

        text = PATH_DEP_RE.sub(rewrite_path_dep, text)

        # dependency_overrides are resolved locally and stripped on upload.
        if override_names:
            overrides = ["dependency_overrides:"]
            for dep_name in sorted(set(override_names)):
                overrides.append(f"  {dep_name}:\n    path: ../{dep_name}")
            text = text.rstrip() + "\n" + "\n".join(overrides) + "\n"

        pubspec.write_text(text)
        missing = [d for d in set(override_names) if (work_dir / d).is_dir() is False]
        if missing:
            raise SystemExit(f"Missing override targets in {name}: {missing}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())