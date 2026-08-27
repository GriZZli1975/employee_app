import 'package:flutter/material.dart';

import 'core/session.dart';
import 'features/home/home_screen.dart';
import 'features/login/login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StooxEmployeeApp());
}

class StooxEmployeeApp extends StatefulWidget {
  const StooxEmployeeApp({super.key});

  @override
  State<StooxEmployeeApp> createState() => _StooxEmployeeAppState();
}

class _StooxEmployeeAppState extends State<StooxEmployeeApp> {
  final _session = EmployeeSession();
  bool _ready = false;
  bool _connected = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    var connected = false;
    try {
      connected = await _session.isConnected;
    } catch (_) {
      connected = false;
    }
    if (!mounted) return;
    setState(() {
      _connected = connected;
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stoox сотрудник',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        useMaterial3: true,
      ),
      home: !_ready
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _connected
              ? HomeScreen(
                  session: _session,
                  onLogout: () => setState(() => _connected = false),
                )
              : LoginScreen(
                  session: _session,
                  onConnected: () => setState(() => _connected = true),
                ),
    );
  }
}
