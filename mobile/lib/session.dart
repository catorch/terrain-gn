import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Tokens, the signed-in user and the chosen language, kept in the platform keystore.
class Session extends ChangeNotifier {
  Session({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  String? accessToken;
  String? refreshToken;
  Map<String, dynamic>? user;
  Locale locale = PlatformDispatcher.instance.locale.languageCode == 'en' ? const Locale('en') : const Locale('fr');

  bool get signedIn => refreshToken != null;

  Future<void> restore() async {
    final saved = await _storage.read(key: 'session');
    final language = await _storage.read(key: 'locale');
    if (language != null) locale = Locale(language);
    if (saved != null) {
      final data = jsonDecode(saved) as Map<String, dynamic>;
      accessToken = data['accessToken'] as String?;
      refreshToken = data['refreshToken'] as String?;
      user = data['user'] as Map<String, dynamic>?;
    }
    notifyListeners();
  }

  Future<void> save(Map<String, dynamic> tokens) async {
    accessToken = tokens['accessToken'] as String;
    refreshToken = tokens['refreshToken'] as String;
    user = (tokens['user'] as Map<String, dynamic>?) ?? user;
    await _storage.write(key: 'session', value: jsonEncode({'accessToken': accessToken, 'refreshToken': refreshToken, 'user': user}));
    notifyListeners();
  }

  Future<void> setUser(Map<String, dynamic> value) async {
    user = value;
    await _storage.write(key: 'session', value: jsonEncode({'accessToken': accessToken, 'refreshToken': refreshToken, 'user': user}));
    notifyListeners();
  }

  Future<void> clear() async {
    accessToken = refreshToken = null;
    user = null;
    await _storage.delete(key: 'session');
    notifyListeners();
  }

  Future<void> setLocale(Locale value) async {
    locale = value;
    await _storage.write(key: 'locale', value: value.languageCode);
    notifyListeners();
  }
}
