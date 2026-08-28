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
  });

  final EmployeeSession session;
  final VoidCallback onLogout;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tabIndex = MainNavBar.inWorkTabIndex;
  String _name = 'Сотрудник';
  int? _employeeId;

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
    if (index == MainNavBar.inWorkTabIndex) {
      _inWorkKey.currentState?.reload();
    } else if (index == 0) {
      _znKey.currentState?.reload();
    } else if (index == 2) {
      _personalKey.currentState?.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_name)),
      body: IndexedStack(
        index: _tabIndex,
        children: [
          ZnTabScreen(key: _znKey, session: widget.session),
          InWorkScreen(key: _inWorkKey, session: widget.session),
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
      ),
    );
  }
}
