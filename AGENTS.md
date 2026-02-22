# Agent Instructions

This guide is for AI agents contributing to this project. Follow these instructions to ensure your contributions are aligned with the project's standards.

## 1. Project Overview

Refer to the `README.md` for the project overview.

## 2. Core Principles

- **Test-Driven Development (TDD)**: Tests MUST be written before the implementation. All new code must have corresponding tests, and all tests must pass before merging.
- **Simplicity**: The implementation should be simple, clean, and easy to understand. Avoid over-engineering.
- **No Dependencies**: The core library must not have any third-party dependencies from `pub.dev`.

## 3. Tech Stack

- **Language**: Dart 3.x (with sound null safety)
- **Testing**: `package:test`
- **Linting**: `package:very_good_analysis` (using Very Good Analysis rules)

## 4. Development Workflow

1.  **Setup**: Execute the `source setup.sh` command to setup the Dart environment.
2.  **Create files/directories**: Create the necessary files and directories.
3.  **Write Tests**: Write failing tests for the feature you are implementing.
4.  **Implement**: Write the code to make the tests pass.
5.  **Polish**: Add documentation, format, and lint the code.
6.  **Submit Changes**: Submit the changes according to format of the `.github/PULL_REQUEST_TEMPLATE.md` file with the following title formats:
    - feat: A new feature
    - fix: A bug fix
    - docs: Documentation only changes
    - style: Changes that do not affect the meaning of the code (white-space, formatting, missing semi-colons, etc)
    - refactor: A code change that neither fixes a bug nor adds a feature
    - perf: A code change that improves performance
    - test: Adding missing tests or correcting existing tests
    - build: Changes that affect the build system or external dependencies (example scopes: gulp, broccoli, npm)
    - ci: Changes to our CI configuration files and scripts (example scopes: Travis, Circle, BrowserStack, SauceLabs)
    - chore: Other changes that don't modify src or test files
    - revert: Reverts a previous commit
    
## 6. Key Commands

- **Access to the main source directory**: `cd pipecat_smart_turn`
- **Run tests**: `flutter test`
- **Lint and analyze**: `flutter analyze`
- **Fix lint and analysis errors**: `dart fix --apply`
- **Format code**: `dart format --line-length 80 lib test`

## 7. Dos and Don'ts

- **DO** follow the TDD process strictly.
- **DO** write clear and descriptive commit messages.
- **DO** execute `dart format --line-length 80 lib test` to format code, also ensure `flutter analyze` and `flutter test` pass before submitting changes.
- **DON'T** add any third-party dependencies to `pubspec.yaml`.
- **DON'T** implement functionality that is not specified in a task.
- **DON'T** modify files outside the scope of your assigned task unless approved by the user.
