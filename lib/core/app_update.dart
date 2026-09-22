import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Проверка обновлений через GitHub Releases репозитория приложения.
///
/// Репозиторий: https://github.com/GriZZli1975/employee_app
/// Процесс релиза: см. `RELEASE.md` в корне приложения.
class AppUpdateChecker {
  static const repoOwner = 'GriZZli1975';
  static const repoName = 'employee_app';
  static const releasesApi =
      'https://api.github.com/repos/$repoOwner/$repoName/releases/latest';
  static const releasesPage =
      'https://github.com/$repoOwner/$repoName/releases/latest';

  /// Сравнить локальную версию с latest release. `null` — обновление не нужно / ошибка сети.
  static Future<AppUpdateInfo?> check() async {
    try {
      final local = await PackageInfo.fromPlatform();
      final res = await http
          .get(
            Uri.parse(releasesApi),
            headers: {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'stoox-employee-app',
              'X-GitHub-Api-Version': '2022-11-28',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 404) return null; // ещё нет релизов
      if (res.statusCode >= 400) return null;

      final data = jsonDecode(res.body);
      if (data is! Map) return null;
      final map = Map<String, dynamic>.from(data);
      if (map['draft'] == true) return null;

      final tag = (map['tag_name'] ?? '').toString().trim();
      if (tag.isEmpty) return null;
      final remote = _parseTag(tag);
      if (remote == null) return null;

      final localBuild = int.tryParse(local.buildNumber) ?? 0;
      final localName = local.version.trim();
      final newer = remote.build != null
          ? remote.build! > localBuild
          : _isVersionNewer(remote.version, localName);
      if (!newer) return null;

      final body = (map['body'] ?? '').toString();
      final force = body.contains('[force]') ||
          body.contains('[обязательно]') ||
          tag.toLowerCase().contains('force');

      final apkUrl = _pickApkUrl(map['assets']);
      return AppUpdateInfo(
        localVersion: localName,
        localBuild: localBuild,
        remoteVersion: remote.version,
        remoteBuild: remote.build,
        tagName: tag,
        apkUrl: apkUrl,
        releaseNotes: body.trim().isEmpty ? null : body.trim(),
        force: force,
        htmlUrl: (map['html_url'] ?? releasesPage).toString(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Показать диалог, если есть обновление. Вызывать после первого кадра (есть context).
  static Future<void> checkAndPrompt(BuildContext context) async {
    final info = await check();
    if (info == null || !context.mounted) return;
    await prompt(context, info);
  }

  static Future<void> prompt(BuildContext context, AppUpdateInfo info) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: !info.force,
      builder: (ctx) => PopScope(
        canPop: !info.force,
        child: AlertDialog(
          title: Text(info.force ? 'Нужно обновить приложение' : 'Доступна новая версия'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Сейчас: ${info.localLabel}\nНовая: ${info.remoteLabel}',
                  style: const TextStyle(height: 1.4),
                ),
                if (info.releaseNotes != null && info.releaseNotes!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    _shortNotes(info.releaseNotes!),
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (!info.force)
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Позже'),
              ),
            FilledButton(
              onPressed: () async {
                final uri = Uri.parse(info.apkUrl ?? info.htmlUrl);
                final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
                if (!ok && ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Не удалось открыть ссылку на обновление')),
                  );
                }
                if (!info.force && ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Обновить'),
            ),
          ],
        ),
      ),
    );
  }

  static String _shortNotes(String raw) {
    final cleaned = raw
        .replaceAll(RegExp(r'\[force\]', caseSensitive: false), '')
        .replaceAll('[обязательно]', '')
        .trim();
    if (cleaned.length <= 400) return cleaned;
    return '${cleaned.substring(0, 400)}…';
  }

  static String? _pickApkUrl(dynamic assets) {
    if (assets is! List) return null;
    for (final a in assets) {
      if (a is! Map) continue;
      final name = (a['name'] ?? '').toString().toLowerCase();
      final url = (a['browser_download_url'] ?? '').toString();
      if (name.endsWith('.apk') && url.startsWith('http')) return url;
    }
    // fallback: любой asset с apk в URL
    for (final a in assets) {
      if (a is! Map) continue;
      final url = (a['browser_download_url'] ?? '').toString();
      if (url.toLowerCase().contains('.apk')) return url;
    }
    return null;
  }

  /// `v1.0.14`, `1.0.14`, `v1.0.14+16`, `1.0.14+16`
  static ({String version, int? build})? _parseTag(String tag) {
    var t = tag.trim();
    if (t.startsWith('v') || t.startsWith('V')) t = t.substring(1);
    // отбросить суффиксы вроде -force
    final main = t.split(RegExp(r'[-_]')).first;
    final plus = main.split('+');
    final version = plus.first.trim();
    if (version.isEmpty || !RegExp(r'^\d+(\.\d+)*$').hasMatch(version)) {
      return null;
    }
    final build = plus.length > 1 ? int.tryParse(plus[1].trim()) : null;
    return (version: version, build: build);
  }

  static bool _isVersionNewer(String remote, String local) {
    List<int> parts(String v) =>
        v.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final a = parts(remote);
    final b = parts(local);
    final n = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x > y) return true;
      if (x < y) return false;
    }
    return false;
  }
}

class AppUpdateInfo {
  AppUpdateInfo({
    required this.localVersion,
    required this.localBuild,
    required this.remoteVersion,
    required this.remoteBuild,
    required this.tagName,
    required this.apkUrl,
    required this.releaseNotes,
    required this.force,
    required this.htmlUrl,
  });

  final String localVersion;
  final int localBuild;
  final String remoteVersion;
  final int? remoteBuild;
  final String tagName;
  final String? apkUrl;
  final String? releaseNotes;
  final bool force;
  final String htmlUrl;

  String get localLabel =>
      localBuild > 0 ? '$localVersion ($localBuild)' : localVersion;

  String get remoteLabel {
    if (remoteBuild != null) return '$remoteVersion ($remoteBuild)';
    return remoteVersion;
  }
}
