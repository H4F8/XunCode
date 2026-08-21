import 'package:flutter/foundation.dart';

import '../services/settings_service.dart';
import '../services/update_service.dart';

/// Мост между фоновым движком обновлений и UI.
///
/// Держит результат последней проверки, управляет «бесячим» красным
/// огоньком (флаг has_update в SharedPreferences) и решает, когда
/// показать экран тотальной блокировки.
class UpdateModel extends ChangeNotifier {
  final SettingsService _settings = SettingsService.instance;

  UpdateCheckResult? _result;
  bool _checking = false;
  bool _hardShown = false;

  UpdateCheckResult? get result => _result;
  bool get checking => _checking;

  /// Установлена последняя версия (или проверка не удалась — офлайн).
  bool get hasUpdate => _result?.hasUpdate ?? false;

  /// Красный огонёк: есть мягкое обновление и юзер ещё не открывал диалог.
  bool get hasSoftBadge =>
      _settings.hasUpdate && !(_result?.hasHardUpdate ?? false);

  /// Критический релиз блокирует платформу пользователя.
  bool get needsHardBlock => _result?.hasHardUpdate ?? false;

  /// Уже показали экран блокировки в этой сессии.
  bool get hardShown => _hardShown;
  void markHardShown() {
    _hardShown = true;
    notifyListeners();
  }

  /// Подхватить уже полученный результат (ручная проверка из настроек),
  /// не выполняя повторный сетевой запрос.
  Future<void> adopt(UpdateCheckResult res) async {
    _result = res;
    if (!res.hasUpdate) {
      await _settings.setHasUpdate(false);
    } else if (!res.hasHardUpdate) {
      await _settings.setHasUpdate(true);
    }
    notifyListeners();
  }

  /// Фоновая проверка при запуске приложения (Шаг 3 ТЗ).
  ///
  /// Ошибка сети игнорируется полностью — офлайн-режим священен.
  Future<void> check() async {
    if (_checking) return;
    _checking = true;
    notifyListeners();
    try {
      final res = await UpdateService.check();
      _result = res;
      if (res == null) return; // офлайн: ничего не меняем
      if (!res.hasUpdate) {
        // Пользователь на последней версии — гасим огонёк.
        await _settings.setHasUpdate(false);
      } else if (!res.hasHardUpdate) {
        // Soft update — зажигаем огонёк до просмотра/обновления.
        await _settings.setHasUpdate(true);
      }
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  /// Юзер посмотрел диалог обновлений (или закрыл его) — гасим огонёк.
  Future<void> dismissSoft() async {
    await _settings.setHasUpdate(false);
    notifyListeners();
  }
}
