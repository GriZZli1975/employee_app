import 'package:flutter/material.dart';

import '../../core/session.dart';
import '../../core/work_order.dart';
import '../../widgets/main_nav_bar.dart';
import '../in_work/in_work_screen.dart';
import '../personal/personal_screen.dart';
import '../works/zn_tab_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.session,
    required this.onLogout,
    required this.dark,
    required this.onToggleTheme,
  });

  final EmployeeSession session;
  final VoidCallback onLogout;
  final bool dark;
  final VoidCallback onToggleTheme;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tabIndex = MainNavBar.inWorkTabIndex;
  String _name = 'Сотрудник';
  int? _employeeId;
  int _inWorkCount = 0;

  final _inWorkKey = GlobalKey<InWorkScreenState>();
  final _znKey = GlobalKey<ZnTabScreenState>();
  final _personalKey = GlobalKey<PersonalScreenState>();

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

  void _onTabSelected(int index) {
    setState(() => _tabIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_name),
        actions: [
          IconButton(
            tooltip: widget.dark ? 'Светлая тема' : 'Тёмная тема',
            onPressed: widget.onToggleTheme,
            icon: Icon(widget.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: [
          ZnTabScreen(key: _znKey, session: widget.session),
          InWorkScreen(
            key: _inWorkKey,
            session: widget.session,
            onCountChanged: (n) {
              if (_inWorkCount == n) return;
              setState(() => _inWorkCount = n);
            },
          ),
          PersonalScreen(
            key: _personalKey,
            session: widget.session,
            employeeName: _name,
            employeeId: _employeeId,
            onLogout: widget.onLogout,
          ),
        ],
      ),
      bottomNavigationBar: MainNavBar(
        selectedIndex: _tabIndex,
        onSelected: _onTabSelected,
        inWorkCount: _inWorkCount,
      ),
    );
  }
}
