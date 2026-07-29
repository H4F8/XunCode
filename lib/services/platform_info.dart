import 'dart:io';

import 'package:flutter/foundation.dart';

/// Платформо-зависимые утилиты и флаги.
///
/// На Android включён режим proot + Alpine + AXS, на desktop-платформах
/// (Linux/macOS/Windows) используется нативная системная оболочка и обычный
/// файловый ввод/вывод без виртуализации.
class PlatformInfo {
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;
  static bool get isLinux => !kIsWeb && Platform.isLinux;
  static bool get isMacOS => !kIsWeb && Platform.isMacOS;
  static bool get isWindows => !kIsWeb && Platform.isWindows;
  static bool get isDesktop =>
      !kIsWeb && (isLinux || isMacOS || isWindows);
  static bool get isMobile => isAndroid; // пока только Android

  /// Человекочитаемое имя платформы.
  static String get label {
    if (isAndroid) return 'Android';
    if (isLinux) return 'Linux';
    if (isMacOS) return 'macOS';
    if (isWindows) return 'Windows';
    return 'Unknown';
  }

  /// Требуется ли на этой платформе Alpine rootfs.
  /// На desktop используется системная оболочка, поэтому rootfs не нужен.
  static bool get needsRootfs => isAndroid;

  /// Доступен ли Tor через Orbot.
  /// На desktop используется обычный SOCKS5/HTTP-прокси.
  static bool get supportsOrbot => isAndroid;

  /// Поддерживает ли платформа нативные горячие клавиши ОС
  /// (Cmd/Ctrl + ... через SingleActivator).
  static bool get supportsNativeShortcuts => isDesktop || isAndroid;

  /// Нужно ли запрашивать MANAGE_EXTERNAL_STORAGE.
  static bool get needsStoragePermission => isAndroid;

  /// Команда для открытия файла/папки в файловом менеджере ОС.
  static String? fileManagerCommand(String path) {
    if (isLinux) {
      return 'xdg-open';
    } else if (isMacOS) {
      return 'open';
    } else if (isWindows) {
      return 'explorer';
    }
    return null;
  }

  /// Путь к пользовательской директории XunCode в формате ОС.
  static String homeDir() {
    try {
      return Platform.environment['HOME'] ?? Directory.current.path;
    } catch (_) {
      return Directory.current.path;
    }
  }
}
