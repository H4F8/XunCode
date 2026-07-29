# XunCode

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Build APK](https://github.com/H4F8/XunCode/actions/workflows/build.yml/badge.svg)](https://github.com/H4F8/XunCode/actions/workflows/build.yml)

> **Open-source code editor for Android and Linux.** Built with Flutter and the Monaco Editor engine. Free to use, modify, and contribute. Licensed under [Apache-2.0](LICENSE).

## Overview

XunCode is a native, cross-platform code editor that brings a desktop-like editing experience to mobile devices and Linux desktops. It combines the Monaco Editor (the same engine powering Visual Studio Code) with a plugin ecosystem, an embedded terminal, and deep customization options.

## Real feature set

### Editor
- **Monaco Editor** — syntax highlighting, bracket matching, auto-indentation, and minimap for 25+ languages including JavaScript, TypeScript, Python, Dart, Go, Rust, C/C++, Java, Kotlin, PHP, Ruby, Lua, HTML, CSS, SCSS, JSON, YAML, Markdown, Shell, SQL, Swift, and XML.
- **Settings** — configurable font size, font family, tab size, word wrap, auto-save, and completion behavior.
- **File tabs** — open multiple files, switch between them, and track unsaved changes.
- **Project sidebar** — browse the projects directory, open files, and navigate the workspace.
- **Command palette** — trigger plugin commands from a searchable list.
- **Status bar** — cursor line/column, active language, and quick Tor toggle.

### Terminal
- **proot + Alpine Linux** — a full user-space Linux environment (no root required).
- **AXS (Acode eXecution Server)** — bypasses Android 13+ `noexec`/`W^X` restrictions using `memfd_create`.
- **Fallback shell** — if Alpine is not installed or unsupported, the app falls back to `/system/bin/sh` on Android.
- **Multiple tabs** — open several terminal sessions at once.
- **On-screen keys** — quick-access row for Ctrl, Esc, Tab, arrow keys, and common symbols.

### Plugins
- **GitHub-based plugins** — install any public repository that contains `plugin.json` + `main.js`.
- **Sandboxed execution** — plugins run inside an isolated `HeadlessInAppWebView` with a permission model.
- **Plugin API** — JavaScript API covering editor access, file system, HTTP requests, terminal/process execution, settings, storage, workspace search, and UI prompts.
- **Marketplace** — browse, install, and review plugins (backend can be self-hosted or deployed on Vercel).
- **Runtime management** — activate, deactivate, reload, and uninstall plugins without restarting the app.

### Customization and runtimes
- **UI language packs** — Russian and English are bundled; additional languages can be added by placing `.txt` files in `Shared/XunCode/Languages/`.
- **Language / runtime installer** — download and install development runtimes such as Python, Node.js, Go, Rust, Ruby, Lua, PHP, Java, or any custom URL.
- **Theme** — VS Code Dark+-inspired color theme with a consistent visual style across the app.

### Networking
- **Proxy support** — HTTP/HTTPS and SOCKS5 proxy configuration.
- **Tor via Orbot** — start/stop Orbot directly from the status bar.

### Platforms
- **Android** — primary target. Minimum SDK 26, recommended Android 10+ (API 29+). Android 13+ support is stabilized through `libaxs.so` and `libproot.so` placed in `jniLibs`.
- **Linux** — desktop build is supported via Flutter's Linux target. The terminal uses the native system shell instead of proot, and the plugin sandbox works out of the box.

## Requirements

| Platform | Minimum version |
|----------|-----------------|
| Android  | API 26 (Android 8.0) |
| Linux    | 64-bit GTK-based desktop |
| Flutter  | 3.24.5 or newer |
| Dart     | 3.3.0 or newer |

## Install

### Android
Download the latest APK from [GitHub Releases](https://github.com/H4F8/XunCode/releases) or grab a CI artifact from the [Actions tab](https://github.com/H4F8/XunCode/actions).

### Linux
Releases are published as AppImage, `.deb`, `.rpm`, and portable tar archives on the [releases page](https://github.com/H4F8/XunCode/releases).

## Build from source

```sh
git clone https://github.com/H4F8/XunCode.git
cd XunCode

# Bundle Monaco Editor assets
npm install && npm run build:monaco

# Fetch Flutter dependencies
flutter pub get

# Generate launcher icons
flutter pub run flutter_launcher_icons

# Android debug APK
flutter build apk --debug

# Linux release
flutter build linux --release
```

For the release Android APK you will need a signing keystore. Set the following repository secrets for CI signing:
- `KEYSTORE_PASSWORD`
- `KEY_ALIAS`
- `KEY_PASSWORD`

## Project layout

```
XunCode/
├── android/            # Android-specific Kotlin code, manifests, and native libs
├── assets/             # Monaco Editor bundle, languages, plugin examples
├── docs/               # Plugin API documentation
├── lib/                # Dart/Flutter source code
├── market/             # Optional Vercel marketplace backend
├── scripts/            # Monaco bundling and build helpers
├── .github/workflows/  # GitHub Actions CI
├── pubspec.yaml
└── README.md
```

## Plugin API

See the full reference in [docs/PLUGIN_API.md](docs/PLUGIN_API.md). Example plugins are located in [example-plugins/](example-plugins/).

## Contributing

Pull requests, bug reports, and feature ideas are welcome.

- GitHub: [@H4F8](https://github.com/H4F8)
- Dev channel: [t.me/XunKal1Dev](https://t.me/XunKal1Dev)
- Community: [t.me/GodPassTGK](https://t.me/GodPassTGK)

## Acknowledgments

- **Acode Foundation** — for the noexec bypass approach on Android 13+ and ready-to-use proot binaries. Repository: [Acode-Foundation/Acode](https://github.com/Acode-Foundation/Acode)
- **bajrangCoder** for **acodex_server (AXS)** — code execution on Android 13+ via `memfd_create`. Repository: [bajrangCoder/acodex_server](https://github.com/bajrangCoder/acodex_server)
- **PRoot** — user-space chroot without root: [proot-me/proot](https://github.com/proot-me/proot)
- **Alpine Linux** — lightweight Linux for the terminal: [alpinelinux.org](https://alpinelinux.org)
- **Monaco Editor** — the code editor engine: [microsoft/monaco-editor](https://github.com/microsoft/monaco-editor)

## License

XunCode is licensed under the [Apache License 2.0](LICENSE).
