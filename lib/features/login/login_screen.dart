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
    required this.dark,
    required this.onToggleTheme,
  });

  final EmployeeSession session;
  final VoidCallback onConnected;
  final bool dark;
  final VoidCallback onToggleTheme;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _botUrlCtrl = TextEditingController();
  final _pcKeyCtrl = TextEditingController();
  final _hostCtrl = TextEditingController();
  final _apiKeyCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _showAdvanced = false;

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
      if (botUrl.isNotEmpty) _botUrlCtrl.text = botUrl;
      if (host.isNotEmpty) {
        _hostCtrl.text = host.replaceFirst(RegExp(r'^https?://'), '');
      }
      if (apiKey.isNotEmpty) _apiKeyCtrl.text = apiKey;
      if (host.isNotEmpty || apiKey.isNotEmpty) _showAdvanced = false;
    });
  }

  @override
  void dispose() {
    _botUrlCtrl.dispose();
    _pcKeyCtrl.dispose();
    _hostCtrl.dispose();
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _scanQr() async {
    final payload = await Navigator.of(context).push<QrPayload>(
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (payload == null || !mounted) return;
    setState(() {
      if (payload.pcKey != null) _pcKeyCtrl.text = payload.pcKey!;
      if (payload.botUrl != null) _botUrlCtrl.text = payload.botUrl!;
      if (payload.host != null) {
        _hostCtrl.text = payload.host!.replaceFirst(RegExp(r'^https?://'), '');
        _showAdvanced = true;
      }
      if (payload.apiKey != null) {
        _apiKeyCtrl.text = payload.apiKey!;
        _showAdvanced = true;
      }
    });
  }

  Future<void> _connect() async {
    final botUrl = EmployeeSession.normalizeBotUrl(_botUrlCtrl.text);
    final pcKey = _pcKeyCtrl.text.trim();
    if (botUrl.isEmpty) {
      setState(() => _error = 'Укажите URL сервиса бота, например https://fo.messagebot.stoox.tech');
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
      await widget.session.saveBotUrl(botUrl);
      await widget.session.savePcKey(pcKey);

      // Всегда спрашиваем бота: он — источник хоста и ключа компании.
      // Ручные поля — только fallback, если bootstrap недоступен.
      String host = '';
      String apiKey = '';
      try {
        final boot = await BotApi(widget.session).bootstrap(botBaseUrl: botUrl, pcKey: pcKey);
        host = (boot['stoox_host'] ?? boot['stoox_base_url'] ?? '').toString().trim();
        apiKey = (boot['stoox_api_key'] ?? '').toString().trim();
        final returnedBot = (boot['bot_base_url'] ?? '').toString().trim();
        if (returnedBot.isNotEmpty) {
          await widget.session.saveBotUrl(returnedBot);
          if (mounted) _botUrlCtrl.text = returnedBot;
        }
        if (mounted) {
          setState(() {
            if (host.isNotEmpty) {
              _hostCtrl.text = host.replaceFirst(RegExp(r'^https?://'), '');
            }
            if (apiKey.isNotEmpty) _apiKeyCtrl.text = apiKey;
          });
        }
      } on BotApiException catch (e) {
        // Fallback на ручной ввод, если бот старый / недоступен
        host = _hostCtrl.text.trim();
        apiKey = _apiKeyCtrl.text.trim();
        if (host.isEmpty || apiKey.isEmpty) {
          rethrow;
        }
        if (mounted) {
          setState(() {
            _showAdvanced = true;
            _error = 'Bootstrap бота не удался ($e). Используем ручной хост/ключ.';
          });
        }
      }

      if (host.isEmpty || apiKey.isEmpty) {
        throw BotApiException(0, 'Нет хоста или ключа компании — проверьте URL бота и PC-ключ');
      }

      await widget.session.saveBaseUrl(host);
      await widget.session.saveApiKey(apiKey);

      final api = StooxApi(widget.session);
      final dash = await api.fetchEmployeeDashboard();
      await widget.session.saveEmployeeCache(dash.summary);

      await BotApi(widget.session).pingMe();

      if (!mounted) return;
      widget.onConnected();
    } on BotApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _showAdvanced = true;
        });
      }
    } on StooxApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _showAdvanced = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: widget.dark ? 'Светлая тема' : 'Тёмная тема',
            onPressed: widget.onToggleTheme,
            icon: Icon(widget.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
          ),
        ],
      ),
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
            Text(
              'Укажите URL бота и PC-ключ. Хост Stoox и ключ компании подтянутся с бота после проверки.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.35),
            ),
            const SizedBox(height: 28),
            TextField(
              controller: _botUrlCtrl,
              decoration: const InputDecoration(
                labelText: 'URL сервиса бота',
                hintText: 'https://fo.messagebot.stoox.tech',
                helperText: 'Адрес Miran / messagebot, не ссылка t.me',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
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
                onPressed: () => setState(() => _showAdvanced = !_showAdvanced),
                child: Text(_showAdvanced ? 'Скрыть ручные настройки' : 'Ручной хост / ключ компании'),
              ),
            ),
            if (_showAdvanced) ...[
              TextField(
                controller: _hostCtrl,
                decoration: const InputDecoration(
                  labelText: 'Хост Stoox (если уже знаете)',
                  hintText: 'fo.stoox.ru',
                  helperText: 'Оставьте пустым — подтянется с бота',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _apiKeyCtrl,
                decoration: const InputDecoration(
                  labelText: 'Ключ компании',
                  helperText: 'Оставьте пустым — подтянется с бота после PC-ключа',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
                autocorrect: false,
              ),
            ],
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
