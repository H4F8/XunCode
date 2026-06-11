# Implementation Plan

[Overview]
Сделать XunCode стабильно работающим на Android 10+, исправить фризы терминала, обойти noexec, переписать README под полностью открытый проект и написать полную документацию по Plugin API.

Проект — Flutter-редактор с Monaco Editor, плагинами, маркетплейсом и встроенным терминалом на proot+Alpine. Текущие проблемы: (1) терминал фризит UI из-за небуферизованного потока событий из Kotlin; (2) WebSocket-handshake к AXS написан вручную и нестабилен; (3) AXS-бинарник копируется в `filesDir`, где на Android 10+ может срабатывать noexec/W^X; (4) нет дебаунса при накоплении терминального вывода; (5) README и лицензия проприетарные; (6) документация Plugin API неполная и содержит устаревшие ссылки. Этот план исправляет всё перечисленное.

[Types]
Никаких новых публичных моделей не требуется — все изменения внутри существующих сервисов и виджетов.

- Внутри `TerminalBridge` добавляется приватное поле `static DateTime? _axsStartTime;` для таймаута старта AXS.
- Внутри `_Tab` в `terminal_panel.dart` добавляется `StringBuilder _pendingBuffer` и `Timer? _flushTimer` для batching.
- В `TerminalSession` добавляется `bool _isClosing = false` для предотвращения двойного закрытия.

[Files]
Изменения коснуться терминального стека, README, лицензии и документации.

- **Новые файлы:**
  - `docs/PLUGIN_API_FULL.md` — полная документация по Plugin API (жизненный цикл, все методы `ctx.*`, примеры, ограничения, публикация).
  - `LICENSE_NEW` — временный файл с Apache-2.0 текстом (затем переименуется в `LICENSE`).

- **Изменения существующих:**
  - `android/app/src/main/kotlin/com/xunkal1/xuncode/TerminalService.kt` — буферизация `pumpOutput`, batching через `StringBuilder` + `Handler`, убрать `sink.endOfStream()` из `finally`, добавить `runCatching` вокруг `sink.success()`.
  - `lib/services/terminal_service.dart` — заменить ручной WebSocket handshake на `WebSocket.connect()` из `dart:io`; добавить таймаут 10 секунд на ожидание порта AXS; переписать `_axsBinary()` чтобы primary путь был `libaxs.so` из `nativeLibraryDir`, а fallback — копирование из assets; убрать `chmod` (не нужен для .so).
  - `lib/widgets/terminal_panel.dart` — добавить `Timer`-based debounce (50 мс) на обновление `ValueNotifier`; вынести `_stripAnsi` в статический `final RegExp` и применять один раз; заменить `jumpTo` на `animateTo` с `Duration.zero` только если пользователь не скроллил вверх; сделать `_handleCtrl` синхронным (убрать `async`/`await`).
  - `lib/screens/editor_screen.dart` — исправить порядок вызова: при открытии терминала сначала подписаться на `EventChannel`, потом вызывать `createUnsandboxed`/`create`.
  - `README.md` — полностью переписать под open-source проект с призывом к контрибьюторам, инструкциями по сборке, ссылками на Telegram и GitHub.
  - `docs/plugin-api.md` — обновить существующий файл, добавить разделы `ctx.terminal`, `ctx.fs`, `ctx.fs.read`, `ctx.fs.write`, `ctx.fs.readdir`, обновить все ссылки на `@H4F8` вместо `@Hinderchik`.
  - `pubspec.yaml` — обновить `description` и `version` (например, `1.1.0+2`).
  - `LICENSE` — заменить на Apache-2.0.

[Functions]
Функции и методы будут изменены или добавлены для устранения фризов и noexec.

- **Новые функции:**
  - `TerminalBridge._axsBinaryFromNativeLib()` → `Future<File>` — возвращает `File('$nativeDir/libaxs.so')`, проверяет `exists()` и `length() > 0`.
  - `TerminalSession._connectWs(int port)` → `Future<WebSocket>` — обёртка `WebSocket.connect('ws://127.0.0.1:$port/terminals/new')` с таймаутом 5 секунд.
  - `TerminalService.pumpOutputBatched(Process, EventSink)` → `void` (private) — читает в `StringBuilder` и отправляет каждые 50 мс или при `
`.
  - `_Tab._flushBuffer()` → `void` (private) — синхронно применяет `_pendingBuffer` к `ValueNotifier`.

- **Изменённые функции:**
  - `TerminalBridge._axsBinary()` — сначала пытаться `_axsBinaryFromNativeLib()`, если не найден — fallback на копирование из assets. Убрать `chmod`.
  - `TerminalBridge._ensureAxs()` — добавить `await Future.any([...stdout.firstWhere..., Future.delayed(Duration(seconds: 10), () => throw TimeoutException)])`.
  - `TerminalSession._open()` — заменить `HttpClient.openUrl` + `WebSocket.fromUpgradedSocket` на `await _connectWs(port)`.
  - `TerminalService.pumpOutput()` → `pumpOutputBatched()` — рефакторинг полностью.
  - `TerminalSession.startSystemSh()` — добавить таймаут 5 секунд на ожидание sink.
  - `_TerminalViewState._handleCtrl(String)` — убрать `async`, убрать `await _send()`, использовать `widget.tab.session.write(...)` напрямую (он и так async, но вызывать без await). Убрать `setState` изнутри `onChanged` — перенести модификацию `_ctrlMod` в `setState` после `if (last >= ...)`.
  - `_Tab._stripAnsi` — убрать из конструктора и перенести во `_flushBuffer`.

- **Удалённые функции:**
  - `TerminalBridge._silent()` — оставить, но внутри `_ensureAxs` убрать лишние вызовы (нет). Не удалять.

[Classes]
Классы модифицируются минимально, чтобы не ломать архитектуру.

- **Изменённые классы:**
  - `TerminalService` (`TerminalService.kt`) — добавить поле `private val outputHandler = android.os.Handler(android.os.Looper.getMainLooper())` для batched posting. Метод `pumpOutput` заменяется на `pumpOutputBatched`.
  - `TerminalBridge` (`terminal_service.dart`) — добавить `static const _axsTimeout = Duration(seconds: 10);`.
  - `_Tab` (`terminal_panel.dart`) — добавить поля `StringBuffer _pending = StringBuffer();`, `Timer? _flushTimer;`. В конструкторе заменить `listen` на `listen` с `_onChunk`.
  - `_TerminalViewState` — добавить `bool _userScrolledUp = false;` и логику в `_scrollToBottom` (не скроллить если `_userScrolledUp == true`).

[Dependencies]
Новые зависимости не нужны. Все изменения используют stdlib Flutter/Dart/Kotlin.

- **Проверить** в `pubspec.yaml` что `flutter_inappwebview: ^6.0.0` совместим с текущим Flutter SDK (>=3.3.0). Если нет — обновить до `^6.1.0` или `^6.0.0` оставить.
- Убедиться, что `dio` и `http` присутствуют (уже есть).
- Никаких новых пакетов добавлять не требуется.

[Testing]
Ручное тестирование на устройстве/эмуляторе Android 10+ (API 29+). Unit-тесты для batching-логики не пишем, т.к. проект не содержит тестового фреймворка для Kotlin.

- Проверить сборку: `flutter build apk --debug`.
- Проверить терминал: открытие, ввод `ls`, `whoami`, `apk add`, отсутствие фризов при `cat /proc/cpuinfo`.
- Проверить noexec: на Android 13 (API 33) эмуляторе убедиться, что AXS запускается через `libaxs.so` без `chmod`.
- Проверить WebSocket handshake: убедиться, что `/terminals/new` возвращает 101 и не падает.
- Проверить README: отображение на GitHub, корректность бейджей.
- Проверить plugin docs: открытие `plugin-docs.html` в редакторе и отображение Markdown.

[Implementation Order]
Логическая последовательность: сначала Kotlin-side (источник фризов), потом Dart-side (потребитель), потом noexec, потом документация и README.

1. **Обновить `TerminalService.kt`** — внедрить `pumpOutputBatched` с `Handler` и `StringBuilder`, удалить `sink.endOfStream()` из `finally`. Проверить, что проект компилируется.
2. **Обновить `terminal_service.dart`** — рефакторинг `_axsBinary()` для использования `libaxs.so`, добавить `_connectWs()`, добавить таймаут в `_ensureAxs()`.
3. **Обновить `terminal_panel.dart`** — добавить `_pending`/`_flushTimer` в `_Tab`, добавить `_userScrolledUp` в `_TerminalViewState`, убрать `async` из `_handleCtrl`.
4. **Обновить `editor_screen.dart`** — поправить порядок подписки на `EventChannel` перед вызовом `create`/`createUnsandboxed`.
5. **Проверить noexec** — запустить на эмуляторе Android 13+, убедиться что `libaxs.so` запускается. Если нет — добавить fallback через `/system/bin/linker64`.
6. **Написать `docs/PLUGIN_API_FULL.md`** — полная документация.
7. **Обновить `docs/plugin-api.md`** — добавить новые разделы, обновить ссылки.
8. **Переписать `README.md`** — open-source, контрибьютеры, инструкции по сборке.
9. **Заменить `LICENSE`** на Apache-2.0.
10. **Обновить `pubspec.yaml`** — description и version.
11. **Сборка и ручное тестирование** — `flutter build apk --debug`.
