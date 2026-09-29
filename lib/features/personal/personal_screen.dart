import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/app_update.dart';
import '../../core/session.dart';
import '../../core/stoox_api.dart';
import '../../core/work_order.dart';
import '../ai/ai_chat_screen.dart';

class PersonalScreen extends StatefulWidget {
  const PersonalScreen({
    super.key,
    required this.session,
    required this.employeeName,
    this.employeeId,
    required this.onLogout,
  });

  final EmployeeSession session;
  final String employeeName;
  final int? employeeId;
  final VoidCallback onLogout;

  @override
  State<PersonalScreen> createState() => PersonalScreenState();
}

class PersonalScreenState extends State<PersonalScreen> {
  bool _loading = false;
  String? _error;
  StooxBalanceInfo? _balance;
  Map<String, dynamic> _summary = {};
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
    reload();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _appVersion = '${info.version} (${info.buildNumber})');
    } catch (_) {}
  }

  Future<void> reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dash = await StooxApi(widget.session).fetchEmployeeDashboard();
      if (!mounted) return;
      setState(() {
        _summary = dash.summary;
        _balance = dash.balance == null ? null : StooxBalanceInfo(dash.balance!);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Выйти?'),
        content: const Text('PC-ключ останется только в Stoox, из приложения будет удалён.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Выйти')),
        ],
      ),
    );
    if (ok == true) widget.onLogout();
  }

  @override
  Widget build(BuildContext context) {
    final name = StooxWorkOrder.employeeNameFromSummary(_summary) ?? widget.employeeName;

    return RefreshIndicator(
      onRefresh: reload,
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (_loading && _balance == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Material(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!),
              ),
            )
          else
            _BalanceCard(
              info: _balance,
              fallbackName: name,
              position: _summary['position_name']?.toString(),
            ),
          const SizedBox(height: 16),
          Text('Сервисы', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.smart_toy_outlined),
                  title: const Text('ИИ-чат'),
                  subtitle: const Text('Справочник и поиск по ремонту'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AiChatScreen(
                          session: widget.session,
                          employeeId: widget.employeeId,
                          employeeName: name,
                        ),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.system_update_outlined),
                  title: const Text('Проверить обновления'),
                  subtitle: Text(_appVersion.isEmpty ? 'GitHub Releases' : 'Версия $_appVersion'),
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Проверяем…'), duration: Duration(seconds: 1)),
                    );
                    final info = await AppUpdateChecker.check();
                    if (!mounted) return;
                    if (info == null) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            _appVersion.isEmpty
                                ? 'Обновлений нет или нет связи с GitHub'
                                : 'У вас актуальная версия $_appVersion',
                          ),
                        ),
                      );
                      return;
                    }
                    await AppUpdateChecker.prompt(context, info);
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Выйти'),
                  onTap: _logout,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.info,
    required this.fallbackName,
    this.position,
  });

  final StooxBalanceInfo? info;
  final String fallbackName;
  final String? position;

  @override
  Widget build(BuildContext context) {
    final rows = info?.rows ?? [];
    final displayName = info?.fullName ?? fallbackName;
    final displayPosition = info?.position ?? position;

    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Баланс и начисления', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(displayName, style: Theme.of(context).textTheme.bodyMedium),
            if (displayPosition != null && displayPosition.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(displayPosition, style: const TextStyle(color: Colors.black54, fontSize: 13)),
            ],
            const SizedBox(height: 12),
            if (rows.isEmpty)
              const Text('Данные баланса недоступны', style: TextStyle(color: Colors.black54))
            else
              ...rows.map((row) {
                final isMain = row.label == 'Текущий баланс';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          row.label,
                          style: TextStyle(
                            fontSize: isMain ? 15 : 13,
                            fontWeight: isMain ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                      Text(
                        StooxFormat.money(row.amount),
                        style: TextStyle(
                          fontSize: isMain ? 22 : 15,
                          fontWeight: isMain ? FontWeight.bold : FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
