import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'session.dart';

class ApiException implements Exception {
  ApiException(this.status, this.code, [this.body = const {}]);
  final int status;
  final String code;
  final Map<String, dynamic> body;

  @override
  String toString() => 'ApiException($status, $code)';
}

const _defaultBase = kIsWeb ? 'http://localhost:4100/v1' : 'http://10.0.2.2:4100/v1';

/// Random key for one logical write, reused across retries so a lost response cannot create a duplicate.
String newIdempotencyKey() {
  final random = Random.secure();
  return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

/// Thin JSON client tuned for flaky networks: short timeouts, retries only when the request is
/// safe to repeat, and one shared token refresh no matter how many requests got a 401.
class Api {
  Api(this.session, {http.Client? client, String? baseUrl, this.retryDelay = const Duration(milliseconds: 800)})
      : _http = client ?? http.Client(),
        baseUrl = baseUrl ?? const String.fromEnvironment('API_URL', defaultValue: _defaultBase);

  final Session session;
  final String baseUrl;
  final Duration retryDelay;
  final http.Client _http;
  Future<void>? _refreshing;

  Future<Map<String, dynamic>> get(String path, {Map<String, String?> query = const {}}) =>
      _send('GET', path, query: query, retry: true);

  Future<Map<String, dynamic>> post(String path, [Object? body, String? idempotencyKey, bool retry = false]) =>
      _send('POST', path, body: body, idempotencyKey: idempotencyKey, retry: retry || idempotencyKey != null);

  Future<Map<String, dynamic>> patch(String path, Object body) => _send('PATCH', path, body: body);

  Future<void> upload(String url, Map<String, String> headers, Uint8List bytes) async {
    final response = await _http.put(Uri.parse(url), headers: headers, body: bytes).timeout(const Duration(minutes: 2));
    if (response.statusCode >= 300) throw ApiException(response.statusCode, 'UPLOAD_FAILED');
  }

  Future<Map<String, dynamic>> _send(String method, String path,
      {Object? body, Map<String, String?> query = const {}, String? idempotencyKey, bool retry = false}) async {
    final params = {for (final e in query.entries) if (e.value != null) e.key: e.value!};
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: params.isEmpty ? null : params);
    var refreshed = false;
    for (var attempt = 0;; attempt++) {
      final request = http.Request(method, uri)
        ..headers['content-type'] = 'application/json'
        ..headers['accept-language'] = session.locale.languageCode;
      if (session.accessToken != null) request.headers['authorization'] = 'Bearer ${session.accessToken}';
      if (idempotencyKey != null) request.headers['idempotency-key'] = idempotencyKey;
      if (body != null) request.body = jsonEncode(body);
      http.Response response;
      try {
        response = await http.Response.fromStream(await _http.send(request).timeout(const Duration(seconds: 20)));
      } on Exception {
        if (!retry || attempt >= 2) throw ApiException(0, 'NETWORK');
        await Future<void>.delayed(retryDelay * (attempt + 1));
        continue;
      }
      final decoded = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 401 && !refreshed && session.refreshToken != null && !path.startsWith('/auth/')) {
        refreshed = true;
        await refreshTokens();
        if (session.signedIn) continue;
      }
      if (response.statusCode >= 400) throw ApiException(response.statusCode, decoded['code'] as String? ?? 'HTTP_${response.statusCode}', decoded);
      return decoded;
    }
  }

  /// Single-flight: the server revokes every session when a rotated refresh token is replayed,
  /// so concurrent 401s must share one refresh call.
  Future<void> refreshTokens() => _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<void> _doRefresh() async {
    try {
      await session.save(await _send('POST', '/auth/refresh', body: {'refreshToken': session.refreshToken}));
    } on ApiException catch (error) {
      if (error.status == 401) await session.clear();
    }
  }
}
