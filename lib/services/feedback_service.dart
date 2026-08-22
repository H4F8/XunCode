import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import 'github_oauth_service.dart';

/// Отправка сообщений о проблемах напрямую разработчику через
/// Telegram Bot API — бесплатно, без своего сервера.
///
/// Настройка (5 минут):
///  1. В Telegram напишите @BotFather: /newbot → получите токен вида
///     `1234567890:AA...`.
///  2. Напишите своему новому боту любое сообщение (чтобы он знал вас).
///  3. Откройте `https://api.telegram.org/bot<ТОКЕН>/getUpdates` и найдите
///     `"chat":{"id":123456789,...}` — это ваш chat_id.
///  4. Впишите оба значения ниже и соберите APK.
///
/// Токен лежит в клиенте и технически извлекаем; бот принимает только
/// сообщения в ваш чат, риски ограничиваются спамом вам в Telegram.
class FeedbackService {
  static const _botToken = 'PUT_BOT_TOKEN_HERE';
  static const _chatId = 'PUT_CHAT_ID_HERE';

  /// Каталог приложений разработчика (самохостинг).
  static const marketUrl = 'https://xuncode-market.vercel.app/';

  /// База API каталога (без завершающего слэша).
  static const _apiBase = 'https://xuncode-market.vercel.app';

  /// Вкладка «Идеи» каталога — туда ведёт кнопка в форме обратной связи.
  static const ideasUrl = '$marketUrl#ideas';

  static bool get configured =>
      !_botToken.startsWith('PUT_') && !_chatId.startsWith('PUT_');

  /// Вошёл ли пользователь в GitHub на мобильном.
  static Future<bool> get signedIn async =>
      (await GithubOAuthService.getToken())?.isNotEmpty ?? false;

  /// Результат отправки отчёта на сайт.
  /// [error]: auth — нет/просрочена GitHub-сессия; rate_limited — кулдаун
  /// (retryAfterMin минут); network — сеть/недоступность сайта.
  static Future<({bool ok, String error, int retryAfterMin})> sendToSite({
    required String category,
    required String text,
  }) async {
    final token = await GithubOAuthService.getToken();
    if (token == null || token.isEmpty) {
      return (ok: false, error: 'auth', retryAfterMin: 0);
    }
    try {
      final res = await Dio().post<Map<String, dynamic>>(
        '$_apiBase/api/reports/submit',
        data: jsonEncode({'category': category, 'text': text}),
        options: Options(headers: {
          'Content-Type': 'application/json',
          'x-gh-token': token,
        }),
      ).timeout(const Duration(seconds: 20));
      final code = res.statusCode ?? 0;
      if (code == 200 && res.data?['ok'] == true) {
        return (ok: true, error: '', retryAfterMin: 0);
      }
      final err = res.data?['error']?.toString() ?? '';
      if (code == 429 || err.contains('rate_limited')) {
        final min = res.data?['retryAfterMin'];
        return (
          ok: false,
          error: 'rate_limited',
          retryAfterMin: min is int ? min : int.tryParse('$min') ?? 3,
        );
      }
      if (code == 401 || err.contains('auth')) {
        return (ok: false, error: 'auth', retryAfterMin: 0);
      }
      return (ok: false, error: 'server', retryAfterMin: 0);
    } catch (_) {
      return (ok: false, error: 'network', retryAfterMin: 0);
    }
  }

  /// Возвращает true, если Telegram принял сообщение.
  static Future<bool> send({
    required String category,
    required String text,
  }) async {
    if (!configured) return false;
    final diagnostics = <String>[
      'XunCode v1.1.9',
      'OS: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    ].join('\n');
    final message = '$category\n\n$text\n\n---\n$diagnostics';
    try {
      final res = await Dio().post<Map<String, dynamic>>(
        'https://api.telegram.org/bot$_botToken/sendMessage',
        data: jsonEncode({
          'chat_id': _chatId,
          'text': message,
          'parse_mode': 'HTML',
        }),
        options: Options(headers: {'Content-Type': 'application/json'}),
      ).timeout(const Duration(seconds: 15));
      return res.statusCode == 200 &&
          (res.data?['ok'] == true);
    } catch (_) {
      return false;
    }
  }
}
