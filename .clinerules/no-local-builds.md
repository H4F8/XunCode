## Brief overview
Project-specific rules for XunCode — a Flutter Android code editor with Monaco, plugins, and an embedded terminal. These rules reflect the user's preferences and project constraints observed during collaborative development.

## Communication style
- Use Russian as the primary language for all user-facing communication and inline comments.
- Keep explanations concise. Avoid lengthy philosophical justifications unless the user asks for them.
- When discussing code changes, reference file paths and line ranges explicitly.

## Development workflow
- **Do NOT run `flutter build`, `flutter pub get`, or any compilation commands on the user's local machine.** The user explicitly forbids local builds. Verification is done by code review and logic analysis only.
- Use PLAN MODE for any architectural changes that touch more than three files. The user prefers to review the plan before implementation.
- Follow the implementation order defined in `implementation_plan.md` when it exists. Do not reorder steps arbitrarily.
- Always update `task_progress` checklists to reflect completed, pending, and newly discovered steps.

## Coding best practices
- Prefer **std-lib solutions** over adding new dependencies. The project avoids dependency bloat.
- When modifying Kotlin files, use explicit `runCatching { }` for all bridge calls to the Flutter side to prevent crashes from propagating.
- When modifying Dart files, use `Future.any([...])` with explicit `TimeoutException` for any external process or network waits that lack built-in timeout.
- **Terminal stack changes** must be applied in this order: Kotlin-side (producer) first, then Dart-side (consumer), then UI debounce. This prevents desynchronization.
- Use `StringBuilder`/`StringBuffer` with batching for any high-frequency string accumulation (e.g. terminal output). Never emit per-character updates to the UI thread.
- For `WebSocket` connections, replace manual HTTP-upgrade handshakes with `WebSocket.connect()` from `dart:io` — the manual handshake is known to be unstable on this project.
- **Noexec / W^X bypass:** Always attempt to load native binaries from `nativeLibraryDir` (APK-extracted `.so` files) before falling back to `filesDir` + `chmod`. The `.so` path does not require `chmod` and is exempt from noexec on Android 10+.
- Use `Timer`-based debounce (typically 50 ms) for any `ValueNotifier` or `setState` driven by high-frequency event streams (e.g. terminal output chunks).

## Project context
- **License:** Apache-2.0. Any new file headers must include the standard Apache boilerplate. Do not revert to proprietary wording.
- **GitHub org:** References in docs and URLs must point to `@H4F8` / `github.com/H4F8`, not the legacy `@Hinderchik` handle.
- **Plugin API:** Any new `ctx.*` methods added in Dart must be documented in both `docs/plugin-api.md` and `docs/PLUGIN_API_FULL.md`. Keep the two files synchronized.
- **pubspec.yaml:** Do not bump versions or add new packages without explicit user approval. The current description must remain open-source oriented.

## Other guidelines
- If the user says "примтупай к плану" (or similar), read `implementation_plan.md` first and follow it literally.
- Do not offer to toggle Act/Plan mode manually. If the user wants to switch modes, they will do so via the UI toggle; simply ask them to toggle when needed.
