import 'package:flutter/material.dart';

import '../../core/session.dart';
import '../../core/work_order.dart';
import '../ai/ai_chat_screen.dart';
import '../in_work/in_work_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.session,
    required this.onLogout,
  });

  final EmployeeSession session;
  final VoidCallback onLogout;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _name = 'Сотрудник';
  int? _employeeId;
  final _inWorkKey = GlobalKey<InWorkScreenState>();

  @override
  void initState() {
    super.initState();
    _loadName();
  }

  Future<void> _loadName() async {
    final cache = await widget.session.getEmployeeCache();
    if (cache == null || !mounted) return;
    setState(() {
      _name = StooxWorkOrder.employeeNameFromSummary(cache) ?? 'Сотрудник';
      final id = StooxWorkOrder.employeeIdFromSummary(cache);
      _employeeId = id == null ? null : int.tryParse(id);
    });
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
    if (ok == true) {
      await widget.session.disconnect();
      widget.onLogout();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_name),
        actions: [
          IconButton(
            tooltip: 'ИИ без авто',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AiChatScreen(
                    session: widget.session,
                    employeeId: _employeeId,
                    employeeName: _name,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.smart_toy_outlined),
          ),
          IconButton(
            tooltip: 'Выйти',
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: InWorkScreen(key: _inWorkKey, session: widget.session),
    );
  }
}
