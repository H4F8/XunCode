import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

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

  static bool get configured =>
      !_botToken.startsWith('PUT_') && !_chatId.startsWith('PUT_');

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
