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
- **Marketplace** — browse and install plugins from the built-in catalog.

### Customization
- **UI language packs** — Russian and English are bundled; additional languages can be added by placing `.txt` files in `Shared/XunCode/Languages/`.
- **Language / runtime installer** — download and install development runtimes such as Python, Node.js, Go, Rust, Ruby, Lua, PHP, Java, or any custom URL.
- **Theme** — VS Code Dark+-inspired color theme with a consistent visual style across the app.

### Platforms
- **Android** — primary target. Minimum SDK 26, recommended Android 10+ (API 29+). Android 13+ support is stabilized through `libaxs.so` and `libproot.so` placed in `jniLibs`.
- **Linux** — desktop build is supported via Flutter's Linux target. The terminal uses the native system shell instead of proot, and the plugin sandbox works out of the box.

### Smart updates (GitHub Releases)
XunCode has a self-contained update engine with no backend: everything is driven by the release notes published in the [H4F8 releases](https://github.com/H4F8/XunCode/releases).

- **Soft update** — a new feature release shows a red badge on the Settings gear and inside *Settings → Software Update*. Opening the dialog shows the release changelog rendered as Markdown; closing it silences the badge until the next release.
- **Hard update** — for critical security fixes the first line of the release body contains a marker:
  ```
  [HARD UPDATE: GITHUB, RUSTORE]
  ```
  The listed install sources get their IDE fully blocked by a full-screen warning with the developer's changelog text; the Back button exits the app entirely. A single **UPDATE NOW** button opens either the direct APK/desktop asset download from the latest release (`browser_download_url`) or the XunCode page inside RuStore.
- **Install-source detection** — on Android the app detects whether it was installed from RuStore (`ru.vk.store`) or elsewhere (GitHub APK / sideload) via `PackageManager.getInstallSourceInfo()`. Desktop builds are always treated as `PC`. While a build is still under RuStore moderation, simply omit `RUSTORE` from the marker — store users will only see the soft badge until you edit the release text.
- **Offline-first safety** — if the network is unavailable or GitHub is unreachable, the check silently fails and the editor keeps working offline. No update logic ever blocks an offline user.

## Coming soon

These features are planned but not ready yet:

- **Marketplace reviews** — plugin ratings and community reviews in the built-in market.
- **Proxy support** — HTTP/HTTPS and SOCKS5 proxy configuration.
- **Tor via Orbot** — start/stop Orbot directly from the status bar.
- **In-app auto-download & install** — one-tap background download of update packages instead of opening a browser/store link.
- **Git repo sync in settings** — cloning and pushing repositories straight from the app UI.

## Requirements

| Platform | Minimum version |
|----------|-----------------|
| Android non-root | API 26 (Android 8.0), user-space proot + Alpine |
| Android root     | API 26+, emulated root inside proot, extended tools |
| Linux            | 64-bit GTK-based desktop |
| Flutter  | 3.24.5 or newer |
| Dart     | 3.3.0 or newer |

## Install

### Android
Two APK variants are published:

- **`xuncode-*-nonroot-release.apk`** — works on any Android 8+ device. It runs a user-space Alpine Linux environment through proot. No root access on the device is required.
- **`xuncode-*-root-release.apk`** — same engine, but the Alpine environment starts as emulated `root` inside proot. Useful for tools that expect root privileges, package managers, and broader filesystem access inside the sandbox.

Download the latest APKs from [GitHub Releases](https://github.com/H4F8/XunCode/releases) or grab CI artifacts from the [Actions tab](https://github.com/H4F8/XunCode/actions).

### Linux
Releases are published as AppImage, `.deb`, `.rpm`, and portable tar archives on the [releases page](https://github.com/H4F8/XunCode/releases).

## Build from source

```sh
git clone https://github.com/H4F8/XunCode.git
cd XunCode

# Bundle Monaco Editor assets
npm install && npm run build:monaco

# (Optional) Bundle Alpine rootfs into the APK
# Skip this to let the app download rootfs on first launch.
./scripts/bundle-rootfs.sh aarch64

# Fetch Flutter dependencies
flutter pub get

# Generate launcher icons
dart run flutter_launcher_icons

# Android debug APKs — pick a flavor
flutter build apk --debug --flavor nonroot
flutter build apk --debug --flavor root

# Linux release
flutter build linux --release
```

For the release Android APK you will need a signing keystore. The CI signs release APKs automatically from repository secrets:

| Secret | Meaning |
|--------|---------|
| `KEYSTORE_BASE64` | your keystore file, base64-encoded |
| `KEYSTORE_PASSWORD` | keystore password |
| `KEY_ALIAS` | key alias inside the keystore |
| `KEY_PASSWORD` | key password |

Generate a keystore once and put it into secrets:

```sh
keytool -genkey -v -keystore upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias xuncode
base64 -w0 upload-keystore.jks   # Linux; macOS: base64 -i upload-keystore.jks
```

Then add the four secrets in *Settings → Secrets and variables → Actions*. If `KEYSTORE_BASE64` is missing, CI falls back to debug signing with a warning — never publish such an APK.

For local release builds you can instead create `android/key.properties`:

```properties
storeFile=/absolute/path/upload-keystore.jks
storePassword=***
keyAlias=xuncode
keyPassword=***
```

`key.properties` and any `*.jks` must never be committed (already gitignored).

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

## Publishing a release (for maintainers)

1. Push a tag / create a Release in the repo and attach the built APK/AppImage assets.
2. For a regular release write free-form Markdown — users get the soft badge.
3. For a critical release make the **first line** of the body:
   ```
   [HARD UPDATE: GITHUB]
   ```
   Add `RUSTORE` to the list only after the build passes moderation, then just edit the release text — the block activates instantly for store users.

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
- **PRoot** — user-space chroot without root: [proot-me/proot](https://proot-me.github.io)
- **Alpine Linux** — lightweight Linux for the terminal: [alpinelinux.org](https://alpinelinux.org)
- **Monaco Editor** — the code editor engine: [microsoft/monaco-editor](https://github.com/microsoft/monaco-editor)

## License

XunCode is licensed under the [Apache License 2.0](LICENSE).
