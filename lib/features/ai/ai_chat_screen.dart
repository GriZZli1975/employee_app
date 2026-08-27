import 'package:flutter/material.dart';

import '../../core/bot_api.dart';
import '../../core/session.dart';
import '../../core/work_order.dart';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({
    super.key,
    required this.session,
    this.order,
    this.employeeId,
    this.employeeName,
  });

  final EmployeeSession session;
  final StooxWorkOrder? order;
  final int? employeeId;
  final String? employeeName;

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _ChatLine {
  _ChatLine({required this.role, required this.text});

  final String role;
  final String text;
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_ChatLine>[];
  String? _conversationId;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _context() {
    final order = widget.order;
    if (order == null) return null;
    return {
      if (order.clientId != null) 'client_id': order.clientId,
      if (order.carId != null) 'car_id': order.carId,
      if (order.saleId != null) 'sale_id': order.saleId,
      if (order.client != null) 'client_name': order.client,
      if (order.carInfo.isNotEmpty) 'car_info': order.carInfo,
      if (order.regNumber != null) 'extra': {'plate': order.regNumber},
    };
  }

  Future<int?> _employeeId() async {
    if (widget.employeeId != null) return widget.employeeId;
    final cache = await widget.session.getEmployeeCache();
    if (cache == null) return null;
    final raw = StooxWorkOrder.employeeIdFromSummary(cache);
    return raw == null ? null : int.tryParse(raw);
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _loading) return;
    final employeeId = await _employeeId();
    if (employeeId == null) {
      setState(() => _error = 'Нет employee_id — переподключитесь к Stoox');
      return;
    }

    setState(() {
      _messages.add(_ChatLine(role: 'user', text: text));
      _input.clear();
      _loading = true;
      _error = null;
    });
    _scrollToEnd();

    try {
      final res = await BotApi(widget.session).chat(
        message: text,
        employeeId: employeeId,
        employeeName: widget.employeeName,
        conversationId: _conversationId,
        context: _context(),
      );
      _conversationId = res['conversation_id']?.toString() ?? _conversationId;
      final reply = res['reply'];
      var replyText = '';
      if (reply is Map) {
        replyText = reply['content']?.toString() ?? reply['text']?.toString() ?? '';
      }
      if (replyText.isEmpty) replyText = res['text']?.toString() ?? 'Пустой ответ';
      if (!mounted) return;
      setState(() => _messages.add(_ChatLine(role: 'assistant', text: replyText)));
    } on BotApiException catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
      _scrollToEnd();
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    return Scaffold(
      appBar: AppBar(
        title: Text(order == null ? 'ИИ-чат' : (order.regNumber ?? 'ИИ-чат')),
      ),
      body: Column(
        children: [
          if (order != null)
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.directions_car_outlined),
                title: Text(order.regNumber ?? order.saleNumber),
                subtitle: Text(order.carInfo),
              ),
            ),
          if (_error != null)
            Material(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!),
              ),
            ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_loading ? 1 : 0),
              itemBuilder: (context, index) {
                if (_loading && index == _messages.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                final msg = _messages[index];
                final mine = msg.role == 'user';
                return Align(
                  alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width * 0.85,
                    ),
                    decoration: BoxDecoration(
                      color: mine
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SelectableText(msg.text),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Вопрос по авто или работам…',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _loading ? null : _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
