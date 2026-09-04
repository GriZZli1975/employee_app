import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class QrPayload {
  const QrPayload({this.pcKey, this.host, this.apiKey, this.botUrl});

  final String? pcKey;
  final String? host;
  final String? apiKey;
  final String? botUrl;
}

/// Сессия сотрудника: хост Stoox, ключ компании, PC-ключ, URL бота.
class EmployeeSession {
  EmployeeSession({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;
  static const _timeout = Duration(seconds: 8);

  static const _pcKeyKey = 'emp_pc_key';
  static const _apiKeyKey = 'emp_api_key';
  static const _baseUrlKey = 'emp_base_url';
  static const _botUrlKey = 'emp_bot_url';
  static const _employeeKey = 'emp_cache';
  static const _themeKey = 'emp_theme_dark';
  static const _draftPrefix = 'emp_capture_draft_';

  String? _pcKey;
  String? _apiKey;
  String? _baseUrl;
  String? _botUrl;
  Map<String, dynamic>? _employee;

  Future<bool> get isConnected async {
    final key = await getPcKey();
    final host = await getBaseUrl();
    return key != null && key.isNotEmpty && host.isNotEmpty;
  }

  static String normalizeBaseUrl(String url) {
    var u = _stripToHostPath(url);
    if (u.isEmpty) return '';
    for (final suffix in ['/outer/api/v1', '/outer/api', '/api/v1', '/api']) {
      if (u.toLowerCase().endsWith(suffix)) {
        u = u.substring(0, u.length - suffix.length);
        break;
      }
    }
    return 'https://${u.replaceAll(RegExp(r'/+$'), '')}';
  }

  static String normalizeBotUrl(String url) {
    final u = _stripToHostPath(url);
    if (u.isEmpty) return '';
    return 'https://${u.replaceAll(RegExp(r'/+$'), '')}';
  }

  /// Убирает повторные/сломанные `http://`, `https://`, `http//` и пробелы.
  static String _stripToHostPath(String url) {
    var u = url.trim().replaceAll(RegExp(r'\s+'), '');
    if (u.isEmpty) return '';
    while (true) {
      final lower = u.toLowerCase();
      if (lower.startsWith('https://')) {
        u = u.substring(8);
      } else if (lower.startsWith('http://')) {
        u = u.substring(7);
      } else if (lower.startsWith('https:/')) {
        u = u.substring(7);
      } else if (lower.startsWith('http:/')) {
        u = u.substring(6);
      } else if (lower.startsWith('https//')) {
        u = u.substring(7);
      } else if (lower.startsWith('http//')) {
        u = u.substring(6);
      } else {
        break;
      }
    }
    return u.replaceFirst(RegExp(r'^/+'), '');
  }

  Future<void> savePcKey(String key) async {
    _pcKey = key.trim();
    await _storage.write(key: _pcKeyKey, value: _pcKey).timeout(_timeout);
  }

  Future<String?> getPcKey() async {
    if (_pcKey != null && _pcKey!.isNotEmpty) return _pcKey;
    try {
      _pcKey = await _storage.read(key: _pcKeyKey).timeout(_timeout);
      return _pcKey;
    } on TimeoutException {
      return null;
    }
  }

  Future<void> saveApiKey(String key) async {
    _apiKey = key.trim();
    await _storage.write(key: _apiKeyKey, value: _apiKey).timeout(_timeout);
  }

  Future<String> getApiKey() async {
    if (_apiKey != null && _apiKey!.isNotEmpty) return _apiKey!;
    try {
      final saved = await _storage.read(key: _apiKeyKey).timeout(_timeout);
      if (saved != null && saved.isNotEmpty) {
        _apiKey = saved;
        return saved;
      }
    } on TimeoutException {
      // ignore
    }
    return '';
  }

  Future<void> saveBaseUrl(String url) async {
    _baseUrl = normalizeBaseUrl(url);
    await _storage.write(key: _baseUrlKey, value: _baseUrl).timeout(_timeout);
  }

  Future<String> getBaseUrl() async {
    if (_baseUrl != null && _baseUrl!.isNotEmpty) return _baseUrl!;
    try {
      final saved = await _storage.read(key: _baseUrlKey).timeout(_timeout);
      if (saved != null && saved.isNotEmpty) {
        _baseUrl = normalizeBaseUrl(saved);
        return _baseUrl!;
      }
    } on TimeoutException {
      // ignore
    }
    return '';
  }

  Future<void> saveBotUrl(String url) async {
    _botUrl = normalizeBotUrl(url);
    await _storage.write(key: _botUrlKey, value: _botUrl).timeout(_timeout);
  }

  Future<String> getBotUrl() async {
    if (_botUrl != null && _botUrl!.isNotEmpty) {
      _botUrl = normalizeBotUrl(_botUrl!);
      return _botUrl!;
    }
    try {
      final saved = await _storage.read(key: _botUrlKey).timeout(_timeout);
      if (saved != null && saved.isNotEmpty) {
        _botUrl = normalizeBotUrl(saved);
        return _botUrl!;
      }
    } on TimeoutException {
      // ignore
    }
    return '';
  }

  Future<void> saveEmployeeCache(Map<String, dynamic> data) async {
    _employee = data;
    await _storage.write(key: _employeeKey, value: jsonEncode(data)).timeout(_timeout);
  }

  Future<Map<String, dynamic>?> getEmployeeCache() async {
    if (_employee != null) return _employee;
    try {
      final raw = await _storage.read(key: _employeeKey).timeout(_timeout);
      if (raw == null || raw.isEmpty) return null;
      final data = jsonDecode(raw);
      if (data is Map<String, dynamic>) {
        _employee = data;
        return data;
      }
      if (data is Map) {
        _employee = Map<String, dynamic>.from(data);
        return _employee;
      }
    } catch (_) {}
    return null;
  }

  Future<void> disconnect() async {
    _pcKey = null;
    _apiKey = null;
    _baseUrl = null;
    _botUrl = null;
    _employee = null;
    try {
      await _storage.delete(key: _pcKeyKey).timeout(_timeout);
      await _storage.delete(key: _apiKeyKey).timeout(_timeout);
      await _storage.delete(key: _baseUrlKey).timeout(_timeout);
      await _storage.delete(key: _botUrlKey).timeout(_timeout);
      await _storage.delete(key: _employeeKey).timeout(_timeout);
    } on TimeoutException {
      // ignore
    }
  }

  Future<bool> getThemeDark() async {
    try {
      final v = await _storage.read(key: _themeKey).timeout(_timeout);
      if (v == '0' || v == 'false') return false;
    } catch (_) {}
    return true;
  }

  Future<void> saveThemeDark(bool dark) async {
    await _storage.write(key: _themeKey, value: dark ? '1' : '0').timeout(_timeout);
  }

  String _draftKey(String kind, int? carId, String? plate) =>
      '$_draftPrefix${kind}_${carId ?? plate ?? 'none'}';

  Future<Map<String, dynamic>?> loadCaptureDraft({
    required String kind,
    int? carId,
    String? plate,
  }) async {
    try {
      final raw = await _storage.read(key: _draftKey(kind, carId, plate)).timeout(_timeout);
      if (raw == null || raw.isEmpty) return null;
      final data = jsonDecode(raw);
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
    } catch (_) {}
    return null;
  }

  Future<void> saveCaptureDraft({
    required String kind,
    int? carId,
    String? plate,
    required Map<String, dynamic> draft,
  }) async {
    await _storage
        .write(key: _draftKey(kind, carId, plate), value: jsonEncode(draft))
        .timeout(_timeout);
  }

  Future<void> clearCaptureDraft({
    required String kind,
    int? carId,
    String? plate,
  }) async {
    try {
      await _storage.delete(key: _draftKey(kind, carId, plate)).timeout(_timeout);
    } catch (_) {}
  }

  static QrPayload parseQr(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const QrPayload();

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        return QrPayload(
          pcKey: _firstString(decoded, ['pc_key', 'pc-key', 'token']),
          host: _firstString(decoded, ['host', 'base_url', 'url', 'stoox_host']),
          apiKey: _firstString(decoded, ['key', 'api_key', 'company_key']),
          botUrl: _firstString(decoded, ['bot_url', 'bot', 'webhook']),
        );
      }
    } catch (_) {}

    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.hasQuery) {
      return QrPayload(
        pcKey: _firstQuery(uri, ['pc_key', 'pc-key', 'token']),
        host: _firstQuery(uri, ['host', 'base_url', 'url']),
        apiKey: _firstQuery(uri, ['key', 'api_key']),
        botUrl: _firstQuery(uri, ['bot_url', 'bot']),
      );
    }

    if (trimmed.startsWith(r'$2y$') || trimmed.startsWith(r'$2a$') || trimmed.length >= 16) {
      return QrPayload(pcKey: trimmed);
    }
    return const QrPayload();
  }

  static String? _firstString(Map map, List<String> keys) {
    for (final key in keys) {
      final v = map[key];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
    }
    return null;
  }

  static String? _firstQuery(Uri uri, List<String> keys) {
    for (final key in keys) {
      final v = uri.queryParameters[key];
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }
}
