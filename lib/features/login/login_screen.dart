import 'package:flutter/material.dart';

import '../../core/bot_api.dart';
import '../../core/session.dart';
import '../../core/stoox_api.dart';
import 'qr_scanner_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.session,
    required this.onConnected,
  });

  final EmployeeSession session;
  final VoidCallback onConnected;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _hostCtrl = TextEditingController(text: 'fo.stoox.ru');
  final _apiKeyCtrl = TextEditingController();
  final _pcKeyCtrl = TextEditingController();
  final _botUrlCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _showBotUrl = false;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final host = await widget.session.getBaseUrl();
    final apiKey = await widget.session.getApiKey();
    final botUrl = await widget.session.getBotUrl();
    if (!mounted) return;
    setState(() {
      if (host.isNotEmpty) _hostCtrl.text = host.replaceFirst(RegExp(r'^https?://'), '');
      if (apiKey.isNotEmpty) _apiKeyCtrl.text = apiKey;
      if (botUrl.isNotEmpty) {
        _botUrlCtrl.text = botUrl;
        _showBotUrl = true;
      }
    });
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _apiKeyCtrl.dispose();
    _pcKeyCtrl.dispose();
    _botUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _scanQr() async {
    final payload = await Navigator.of(context).push<QrPayload>(
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (payload == null || !mounted) return;
    setState(() {
      if (payload.pcKey != null) _pcKeyCtrl.text = payload.pcKey!;
      if (payload.host != null) {
        _hostCtrl.text = payload.host!.replaceFirst(RegExp(r'^https?://'), '');
      }
      if (payload.apiKey != null) _apiKeyCtrl.text = payload.apiKey!;
      if (payload.botUrl != null) {
        _botUrlCtrl.text = payload.botUrl!;
        _showBotUrl = true;
      }
    });
  }

  Future<void> _connect() async {
    final host = _hostCtrl.text.trim();
    final apiKey = _apiKeyCtrl.text.trim();
    final pcKey = _pcKeyCtrl.text.trim();
    if (host.isEmpty) {
      setState(() => _error = 'Укажите хост Stoox, например fo.stoox.ru');
      return;
    }
    if (apiKey.isEmpty) {
      setState(() => _error = 'Укажите ключ компании (key копии Stoox)');
      return;
    }
    if (pcKey.isEmpty) {
      setState(() => _error = 'Введите PC-ключ или отсканируйте QR');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await widget.session.saveBaseUrl(host);
      await widget.session.saveApiKey(apiKey);
      await widget.session.savePcKey(pcKey);
      if (_botUrlCtrl.text.trim().isNotEmpty) {
        await widget.session.saveBotUrl(_botUrlCtrl.text.trim());
      }

      final api = StooxApi(widget.session);
      final dash = await api.fetchEmployeeDashboard();
      await widget.session.saveEmployeeCache(dash.summary);

      var botUrl = EmployeeSession.normalizeBotUrl(_botUrlCtrl.text);
      botUrl = botUrl.isNotEmpty ? botUrl : (await api.fetchBotBaseUrl() ?? '');
      if (botUrl.isNotEmpty) {
        await widget.session.saveBotUrl(botUrl);
        if (mounted) _botUrlCtrl.text = botUrl;
        try {
          await BotApi(widget.session).pingMe();
        } on BotApiException catch (e) {
          if (mounted) {
            setState(() {
              _showBotUrl = true;
              _error = 'Stoox ок, но бот не принял ключ: $e';
              _loading = false;
            });
          }
          return;
        }
      } else {
        setState(() {
          _showBotUrl = true;
          _error = 'Stoox не отдал URL сервиса бота. Укажите адрес Railway, например https://xxx.up.railway.app';
          _loading = false;
        });
        return;
      }

      if (!mounted) return;
      widget.onConnected();
    } on StooxApiException catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          children: [
            Icon(Icons.directions_car, size: 56, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              'Stoox сотрудник',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Вход только через Stoox: хост, ключ компании и PC-ключ.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, height: 1.35),
            ),
            const SizedBox(height: 28),
            TextField(
              controller: _hostCtrl,
              decoration: const InputDecoration(
                labelText: 'Хост Stoox',
                hintText: 'fo.stoox.ru',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              autocorrect: false,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _apiKeyCtrl,
              decoration: const InputDecoration(
                labelText: 'Ключ компании',
                helperText: 'Заголовок key копии Stoox, не PC-ключ',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
              autocorrect: false,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pcKeyCtrl,
              decoration: InputDecoration(
                labelText: 'PC-ключ сотрудника',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: 'Сканировать QR',
                  onPressed: _loading ? null : _scanQr,
                  icon: const Icon(Icons.qr_code_scanner),
                ),
              ),
              minLines: 2,
              maxLines: 4,
              autocorrect: false,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _showBotUrl = !_showBotUrl),
                child: Text(_showBotUrl ? 'Скрыть URL бота' : 'URL сервиса бота (если не подтянулся)'),
              ),
            ),
            if (_showBotUrl)
              TextField(
                controller: _botUrlCtrl,
                decoration: const InputDecoration(
                  labelText: 'URL сервиса бота',
                  hintText: 'https://xxx.up.railway.app',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Material(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!),
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _loading ? null : _connect,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Войти'),
            ),
          ],
        ),
      ),
    );
  }
}
