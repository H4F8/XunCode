import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/plugin.dart';

class ReviewService {
  static const _apiBase = 'https://xuncode-market.vercel.app';
  static const _tokenKey = 'review_user_token';

  static Future<String> getUserToken() async {
    final prefs = await SharedPreferences.getInstance();
    var t = prefs.getString(_tokenKey);
    if (t == null || t.isEmpty) {
      t = _generateToken();
      await prefs.setString(_tokenKey, t);
    }
    return t;
  }

  static String _generateToken() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static Future<List<Review>> fetchReviews(String pluginId) async {
    try {
      final uri = Uri.parse('$_apiBase/api/plugins/review?id=$pluginId');
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return [];
      final body = jsonDecode(res.body);
      if (body is! List) return [];
      return body
          .whereType<Map>()
          .map((e) => Review.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<bool> postReview(String pluginId, int rating, String text) async {
    try {
      final token = await getUserToken();
      final uri = Uri.parse('$_apiBase/api/plugins/review');
      final res = await http
          .post(
            uri,
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'pluginId': pluginId,
              'rating': rating,
              'review': text,
              'userToken': token,
            }),
          )
          .timeout(const Duration(seconds: 15));
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> submitPlugin({
    required String pluginId,
    required String name,
    required String description,
    required String author,
    required String githubUrl,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_apiBase/api/admin/submit'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'pluginId': pluginId,
              'name': name,
              'description': description,
              'author': author,
              'githubUrl': githubUrl,
            }),
          )
          .timeout(const Duration(seconds: 15));
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }
}
