# Dart/Flutter Rules for Guardian IoT

> Project-specific rules for the Guardian IoT codebase. Extends common rules.

## Stack

- **Primary Language**: Dart (Flutter)
- **Firmware**: C++ (Arduino, PlatformIO)
- **Backend**: Firebase (Firestore, RTDB, Auth)
- **Test runner**: `flutter test` for widget/unit tests
- **Analysis**: `flutter analyze` (lints from flutter_lints)

## File Conventions

- Dart: `snake_case` filenames (e.g. `firebase_service.dart`, `device_data.dart`)
- C++: `snake_case` or `kebab-case` filenames (e.g. `guardian_firmware.ino`)
- Test files: `*_test.dart` in the `test/` directory

## Code Style

- Dart 3+ — null safety, records, patterns, sealed classes where applicable
- Prefer `const` constructors; never `var` when you can use `final`
- Keep widgets under 200 lines — extract to separate widget files
- No hardcoded Firebase config or device IDs

## Testing Requirements

- Run `flutter test` before committing
- New services require matching tests
- Firebase-dependent code should use Firebase emulators or mocks

## Markdown / Agent Files

- Agents: YAML frontmatter with `name`, `description`, `tools`, `model`
- Skills: sections — When to Use, How It Works, Examples
- Commands: `description:` frontmatter line required
- Run `npx markdownlint-cli '**/*.md' --ignore node_modules` before committing
