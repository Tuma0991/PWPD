# Guardian IoT Project Guardrails

Generated from project repository analysis. Review before treating it as a hard policy file.

## Commit Workflow

- Prefer `conventional` commit messaging with prefixes such as fix, test, feat, docs.
- Keep new changes aligned with the existing pull-request and review flow already present in the repo.

## Architecture

- Preserve the current Flutter/Dart mobile app with Firebase backend architecture.
- ESP32 firmware uses Arduino C++ with PlatformIO-compatible structure.
- FirebaseService singleton is the single entry point for all Firebase operations.

## Code Style

- Dart: `snake_case` file naming, `PascalCase` classes, `camelCase` functions/variables.
- C++ (ESP32): `SCREAMING_SNAKE_CASE` for constants, `camelCase` for functions.
- Prefer `package:` imports for dependencies, relative imports for project files.

## Project Conventions

- Flutter: Material 3 theme with deep blue primary (#1565C0).
- Firebase: RTDB for real-time sensor streams, Firestore for persistent data.
- Validate risky config changes (Firebase rules, ESP32 credentials) in PRs.

## Detected Workflows

- database-migration: Firebase/Firestore schema changes
- feature-development: Standard feature implementation workflow
- add-language-rules: Adds a new programming language to the rules system, including coding style, hooks, patterns, security, and testing guidelines.

## Review Reminder

- Regenerate this bundle when repository conventions materially change.
- Keep suppressions narrow and auditable.
