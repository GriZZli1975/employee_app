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
  bool _dark = true;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    var connected = false;
    var dark = true;
    try {
      connected = await _session.isConnected;
      dark = await _session.getThemeDark();
    } catch (_) {
      connected = false;
    }
    if (!mounted) return;
    setState(() {
      _connected = connected;
      _dark = dark;
      _ready = true;
    });
  }

  Future<void> _toggleTheme() async {
    final next = !_dark;
    setState(() => _dark = next);
    await _session.saveThemeDark(next);
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF1565C0);
    return MaterialApp(
      title: 'Stoox сотрудник',
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: !_ready
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _connected
              ? HomeScreen(
                  session: _session,
                  dark: _dark,
                  onToggleTheme: _toggleTheme,
                  onLogout: () => setState(() => _connected = false),
                )
              : LoginScreen(
                  session: _session,
                  dark: _dark,
                  onToggleTheme: _toggleTheme,
                  onConnected: () => setState(() => _connected = true),
                ),
    );
  }
}
