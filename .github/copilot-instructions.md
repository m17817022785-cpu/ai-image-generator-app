# Repository Instructions for AI Coding Agents

This repository contains the Flutter Android app **AI Image Generator**. These instructions are persistent project memory and must be followed by GitHub Copilot, coding agents, and future AI assistants.

## Mandatory first step

Before changing this repository, always read:

```text
AGENTS.md
```

`AGENTS.md` is the highest-priority project memory file for stability, signing, build workflow, and anti-regression rules.

## Stability rules

- Do **not** perform large refactors unless the user explicitly asks for them.
- Do **not** rewrite the architecture, migrate state management, or restructure many files just for style.
- Prefer minimal, targeted patches.
- Preserve existing compatibility code, fallback logic, Chinese user-facing messages, timeout handling, model normalization, and image workflow behavior.
- Do not remove working GitHub Actions build/signing logic.

## Build and signing memory

The stable APK build workflow is:

```text
.github/workflows/build_apk.yml
```

Important build facts:

- Java: 17
- Flutter: 3.24.5 stable
- Artifact name: `AI-Image-Generator-release-apk`
- The workflow uses fallback/debug keystore signing to keep APK builds installable and upgradeable.
- Keep `--build-name` and `--build-number` behavior.
- Build numbers must not go backwards.

## Critical files

- `AGENTS.md` — persistent project memory. Always read first.
- `lib/screens/home_screen.dart` — main UI, chat, image generation, parameters, references, new session.
- `lib/services/api_service.dart` — OpenAI-compatible API, image generation/editing, model handling, errors, timeouts.
- `lib/services/settings_service.dart` — persisted settings and panel state.
- `lib/models/message.dart` — message model and OpenAI conversion.
- `.github/workflows/build_apk.yml` — stable Android APK build.
- `pubspec.yaml` — dependencies and version.

## Do not regress these features

- Separate chat/image API Key and Base URL settings.
- Empty image API settings fall back to chat settings.
- Text-to-image and image-to-image support.
- Multiple reference images.
- Image count 1..4.
- Aspect ratio and quality options.
- New session button that clears current chat but keeps settings.
- Collapsible studio header with persisted collapsed state.
- Friendly errors for empty API responses, HTML responses, timeouts, socket errors, and model routing errors.
- RangeError prevention for empty `choices` or `data` arrays.

## Preferred workflow

1. Read `AGENTS.md`.
2. Read relevant source files.
3. Make the smallest safe change.
4. Run/trigger `.github/workflows/build_apk.yml` when APK validation is needed.
5. Report the Actions run and artifact.

Do not weaken or delete this file unless the user explicitly asks.