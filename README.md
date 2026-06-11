# XunCode for Android

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Build APK](https://img.shields.io/badge/Build%20APK-passing-brightgreen)](https://github.com/H4F8/XunCode/actions/workflows/build.yml)

> **Open-source code editor for Android.** Free to use, modify, and contribute. Licensed under [Apache-2.0](LICENSE).

---

## Русский

**XunCode — мощный редактор кода для Android.** Нативное Flutter-приложение с движком Monaco Editor, GitHub-плагинами, плагин-маркетплейсом, поддержкой Tor через Orbot и встроенным proot-терминалом с Alpine Linux.

### Возможности
- Monaco Editor — тот же движок, что в VS Code, подсветка для 25+ языков.
- IntelliSense по всему проекту, переход к определению, переименование.
- **Мультиязычность:** Русский / English «из коробки», любой `.txt` в `Shared/XunCode/Languages/` добавляет новый язык интерфейса.
- **Установка языков программирования:** Python, Node.js, Go, Rust, Ruby, Lua, PHP, Java + любые свои сборки по URL.
- Плагин-система: GitHub-репо с `plugin.json` + `main.js`, песочница на InAppWebView.
- Маркетплейс плагинов (Vercel-бэкенд) с рейтингами и отзывами.
- Терминал proot + Alpine, fallback на `/system/bin/sh`.
- Прокси: HTTP/HTTPS, SOCKS5, Tor через Orbot.
- Запуск кода: Python, JS/Node, PHP, HTML/CSS preview, Java, C/C++.

### Требования
Android 10+ (API 29). Работа на Android 13+ стабилизирована через `libaxs.so` (обход noexec/W^X).

### Установка
- **APK:** [GitHub Releases](https://github.com/H4F8/XunCode/releases) или [артефакты CI](https://github.com/H4F8/XunCode/actions).

### Сборка из исходников
```sh
git clone https://github.com/H4F8/XunCode.git
cd XunCode
npm install && npm run build:monaco
flutter pub get
flutter pub run flutter_launcher_icons
flutter build apk --debug
```

### Контрибьюция
Мы рады PR, issues и идеям! Смотрите [docs/PLUGIN_API_FULL.md](docs/PLUGIN_API_FULL.md) для документации по Plugin API.
- GitHub: [@H4F8](https://github.com/H4F8)
- Dev-канал: [t.me/XunKal1Dev](https://t.me/XunKal1Dev)
- Сообщество: [t.me/GodPassTGK](https://t.me/GodPassTGK)

### Благодарности / Acknowledgments
- **Acode Foundation** — за подход к обходу noexec на Android 13+ и готовые бинарники proot.
  Репозиторий: [https://github.com/Acode-Foundation/Acode](https://github.com/Acode-Foundation/Acode)
- **bajrangCoder** за **acodex_server (AXS)** — решение проблемы выполнения кода на Android 13+ через memfd_create.
  Репозиторий: [https://github.com/bajrangCoder/acodex_server](https://github.com/bajrangCoder/acodex_server)

### Используемые компоненты / Components
- **PRoot** — пользовательский chroot без root: [https://github.com/proot-me/proot](https://github.com/proot-me/proot)
- **Alpine Linux** — лёгкий Linux для терминала: [https://alpinelinux.org](https://alpinelinux.org)
- **AXS (Acode eXecution Server)** — обход noexec через memfd_create: [https://github.com/bajrangCoder/acodex_server](https://github.com/bajrangCoder/acodex_server)

---

## English

**XunCode is an open-source code editor for Android.** A native Flutter app with the Monaco Editor engine, GitHub-based plugins, a plugin marketplace, Tor support via Orbot, and an embedded proot terminal running Alpine Linux.

### Features
- Monaco Editor — same engine as VS Code, syntax highlighting for 25+ languages.
- Project-wide IntelliSense, go-to-definition, rename.
- **Multi-language UI:** Russian / English out of the box; drop any `.txt` into `Shared/XunCode/Languages/` to add another language.
- **Install runtimes:** Python, Node.js, Go, Rust, Ruby, Lua, PHP, Java, plus any custom build by URL.
- Plugin system — GitHub repos with `plugin.json` + `main.js`, sandboxed WebView.
- Plugin marketplace (Vercel backend) with ratings and reviews.
- proot + Alpine terminal, falls back to `/system/bin/sh`.
- Proxy: HTTP/HTTPS, SOCKS5, Tor via Orbot.
- Run code: Python, JS/Node, PHP, HTML/CSS preview, Java, C/C++.

### Requirements
Android 10+ (API 29). Stabilized on Android 13+ via `libaxs.so` (noexec/W^X bypass).

### Install
- **APK:** [GitHub Releases](https://github.com/H4F8/XunCode/releases) or [CI artefacts](https://github.com/H4F8/XunCode/actions).

### Build from source
```sh
git clone https://github.com/H4F8/XunCode.git
cd XunCode
npm install && npm run build:monaco
flutter pub get
flutter pub run flutter_launcher_icons
flutter build apk --debug
```

### Contributing
PRs, issues, and ideas are welcome! See [docs/PLUGIN_API_FULL.md](docs/PLUGIN_API_FULL.md) for the full Plugin API reference.
- GitHub: [@H4F8](https://github.com/H4F8)
- Dev channel: [t.me/XunKal1Dev](https://t.me/XunKal1Dev)
- Community: [t.me/GodPassTGK](https://t.me/GodPassTGK)

### Acknowledgments
- **Acode Foundation** — for the noexec bypass approach on Android 13+ and ready-to-use proot binaries.
  Repository: [https://github.com/Acode-Foundation/Acode](https://github.com/Acode-Foundation/Acode)
- **bajrangCoder** for **acodex_server (AXS)** — code execution on Android 13+ via memfd_create.
  Repository: [https://github.com/bajrangCoder/acodex_server](https://github.com/bajrangCoder/acodex_server)

### Components
- **PRoot** — user-space chroot without root: [https://github.com/proot-me/proot](https://github.com/proot-me/proot)
- **Alpine Linux** — lightweight Linux for the terminal: [https://alpinelinux.org](https://alpinelinux.org)
- **AXS (Acode eXecution Server)** — noexec bypass via memfd_create: [https://github.com/bajrangCoder/acodex_server](https://github.com/bajrangCoder/acodex_server)
