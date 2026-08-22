import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/github_user.dart';

/// GitHub OAuth Device Flow client.
///
/// Mobile apps cannot safely embed a client secret, and registering a custom
/// URL scheme for the standard authorization-code flow is fragile across
/// devices. The Device Flow is the canonical fix: the user types a short code
/// at github.com/login/device while the app polls for the access token.
///
/// Steps:
///  1. POST https://github.com/login/device/code  → device_code, user_code, verification_uri, interval
///  2. UI shows user_code; user opens verification_uri (we deeplink it).
///  3. POST https://github.com/login/oauth/access_token with grant_type=device_code
///     every `interval` seconds until we get an access_token or a fatal error.
///  4. Persist the token in flutter_secure_storage.
class GithubOAuthService {
  // Public client_id; safe to embed for Device Flow apps. Override at build
  // time with `--dart-define=GITHUB_CLIENT_ID=...`.
  static const _clientId = String.fromEnvironment(
    'GITHUB_CLIENT_ID',
    defaultValue: 'Iv23lihRr5ozQ4gHw19H',
  );
  static const _scope = 'repo,read:user';

  static const _tokenKey = 'github_access_token';
  static const _userKey = 'github_user';

  static const _storage = FlutterSecureStorage();

  static Dio _dio() => Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'Accept': 'application/json'},
        validateStatus: (_) => true,
      ));

  /// Initiates Device Flow. Returns the response from the start endpoint;
  /// caller should display [userCode] and call [pollForToken].
  static Future<DeviceFlowStart> startDeviceFlow() async {
    final dio = _dio();
    final res = await dio.post(
      'https://github.com/login/device/code',
      data: {'client_id': _clientId, 'scope': _scope},
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );

    final code = res.statusCode ?? 0;
    if (code < 200 || code >= 300) {
      throw Exception('GitHub device-code request failed: HTTP $code');
    }
    final body = res.data is Map ? res.data as Map : json.decode(res.data.toString()) as Map;
    if (body['error'] != null) {
      throw Exception('GitHub error: ${body['error_description'] ?? body['error']}');
    }
    return DeviceFlowStart(
      deviceCode: body['device_code'] as String,
      userCode: body['user_code'] as String,
      verificationUri: body['verification_uri'] as String,
      interval: (body['interval'] as int?) ?? 5,
      expiresIn: (body['expires_in'] as int?) ?? 900,
    );
  }

  /// Polls GitHub for the access token. Streams status updates so the UI can
  /// show a spinner / countdown. Resolves to the token on success.
  static Stream<DeviceFlowStatus> pollForToken(DeviceFlowStart start) async* {
    final dio = _dio();
    final deadline = DateTime.now().add(Duration(seconds: start.expiresIn));
    var interval = start.interval;

    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(Duration(seconds: interval));

      final res = await dio.post(
        'https://github.com/login/oauth/access_token',
        data: {
          'client_id': _clientId,
          'device_code': start.deviceCode,
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      final body = res.data is Map
          ? res.data as Map
          : json.decode(res.data.toString()) as Map;

      if (body['access_token'] is String) {
        final token = body['access_token'] as String;
        await _storage.write(key: _tokenKey, value: token);
        // Best-effort user fetch
        final user = await _fetchUser(token);
        if (user != null) {
          await _storage.write(key: _userKey, value: json.encode(user.toJson()));
        }
        yield DeviceFlowStatus.success(token, user);
        return;
      }

      switch (body['error']) {
        case 'authorization_pending':
          yield DeviceFlowStatus.pending();
          break;
        case 'slow_down':
          interval += 5;
          yield DeviceFlowStatus.pending();
          break;
        case 'expired_token':
          yield DeviceFlowStatus.error('Code expired. Try again.');
          return;
        case 'access_denied':
          yield DeviceFlowStatus.error('Access denied by user.');
          return;
        default:
          yield DeviceFlowStatus.error(
              'OAuth error: ${body['error_description'] ?? body['error'] ?? 'unknown'}');
          return;
      }
    }
    yield DeviceFlowStatus.error('Timed out waiting for authorization.');
  }

  static Future<GithubUser?> _fetchUser(String token) async {
    try {
      final dio = _dio();
      final res = await dio.get(
        'https://api.github.com/user',
        options: Options(headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        }),
      );
      if ((res.statusCode ?? 0) < 200 || (res.statusCode ?? 0) >= 300) return null;
      final data = res.data is Map
          ? res.data as Map<String, dynamic>
          : json.decode(res.data.toString()) as Map<String, dynamic>;
      return GithubUser.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> getToken() => _storage.read(key: _tokenKey);

  static Future<GithubUser?> getUser() async {
    final raw = await _storage.read(key: _userKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return GithubUser.fromJson(json.decode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> isSignedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  static Future<void> signOut() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
  }

  static String get clientId => _clientId;
}

class DeviceFlowStart {
  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final int interval;
  final int expiresIn;
  const DeviceFlowStart({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.interval,
    required this.expiresIn,
  });
}

enum DeviceFlowState { pending, success, error }

class DeviceFlowStatus {
  final DeviceFlowState state;
  final String? error;
  final String? token;
  final GithubUser? user;
  const DeviceFlowStatus._(this.state, {this.error, this.token, this.user});

  factory DeviceFlowStatus.pending() => const DeviceFlowStatus._(DeviceFlowState.pending);
  factory DeviceFlowStatus.error(String msg) =>
      DeviceFlowStatus._(DeviceFlowState.error, error: msg);
  factory DeviceFlowStatus.success(String token, GithubUser? user) =>
      DeviceFlowStatus._(DeviceFlowState.success, token: token, user: user);
}
