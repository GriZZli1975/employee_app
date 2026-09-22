import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/bot_api.dart';
import '../../core/session.dart';
import '../../core/work_order.dart';
import '../../widgets/network_photo.dart';
import '../capture/voice_recorder.dart';
import 'ai_chat_models.dart';
import 'ai_message_bubble.dart';

/// Режим поиска ИИ: auto — как раньше; car — по авто; history — медиатека; web — интернет.
enum AiSearchMode { auto, car, history, web }

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

class _AiChatScreenState extends State<AiChatScreen> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final _scroll = ScrollController();
  final _messages = <AiChatMessage>[];
  final _recorder = VoiceRecorder();
  String? _conversationId;
  bool _loading = false;
  bool _recording = false;
  String? _error;
  AiSearchMode _searchMode = AiSearchMode.web;
  MediaAuth _mediaAuth = const MediaAuth();
  List<AiChatTemplate> _apiTemplates = const [];

  static const _templatesGeneral = [
    'Как провести диагностику подвески — покажи схему',
    'Момент затяжки колёс для этой модели',
    'Как правильно менять передние тормозные колодки — видео',
  ];

  static const _templatesCarLegacy = [
    'Фото диагностики за сегодня',
    'Результаты осмотра за последний визит',
    'Список работ по текущему ЗН',
  ];

  @override
  void initState() {
    super.initState();
    _searchMode = widget.order != null ? AiSearchMode.car : AiSearchMode.web;
    _loadMediaAuth();
    _loadApiTemplates();
  }

  Future<void> _loadMediaAuth() async {
    try {
      final api = BotApi(widget.session);
      final headers = await api.mediaAuthHeaders();
      final base = await api.baseUrl();
      if (!mounted) return;
      setState(() => _mediaAuth = MediaAuth(botBase: base, headers: headers));
    } catch (_) {}
  }

  Future<void> _loadApiTemplates() async {
    final carId = widget.order?.carId;
    if (carId == null) return;
    try {
      final raw = await BotApi(widget.session).fetchTemplates(carId: carId);
      if (!mounted) return;
      setState(() {
        _apiTemplates = raw.map(AiChatTemplate.fromJson).whereType<AiChatTemplate>().toList();
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _recorder.dispose();
    _inputFocus.dispose();
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

  Future<void> _send({
    String? preset,
    String? templateId,
  }) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _loading) return;
    final employeeId = await _employeeId();
    if (employeeId == null) {
      setState(() => _error = 'Нет employee_id — переподключитесь к Stoox');
      return;
    }

    setState(() {
      _messages.add(AiChatMessage(role: 'user', text: text));
      if (preset == null) _input.clear();
      _loading = true;
      _error = null;
    });
    _inputFocus.unfocus();
    _scrollToEnd();

    try {
      final res = await BotApi(widget.session).chat(
        message: text,
        employeeId: employeeId,
        employeeName: widget.employeeName,
        conversationId: _conversationId,
        context: _context(),
        searchMode: templateId != null ? 'web' : _searchMode.name,
        templateId: templateId,
      );
      _conversationId = res['conversation_id']?.toString() ?? _conversationId;
      final reply = res['reply'];
      final rawReplyText = reply is Map
          ? (reply['content'] ?? reply['text'] ?? '').toString()
          : '';
      var replyText = AiChatMessage.stripQuickRepliesBlock(rawReplyText);
      var attachments = AiChatMessage.parseReply(reply);
      var quickReplies = AiQuickReply.parseList(res['quick_replies']);
      if (quickReplies.isEmpty && rawReplyText.isNotEmpty) {
        quickReplies = AiChatMessage.parseEmbeddedQuickReplies(rawReplyText);
      }

      if (AiChatMessage.looksLikeInspectionQuery(text)) {
        final report = res['inspection_report'] ?? (reply is Map ? reply['inspection_report'] : null);
        final reportText = AiChatMessage.formatInspectionReport(report);
        if (reportText.isNotEmpty) {
          final llm = replyText.trim();
          replyText = reportText;
          if (llm.isNotEmpty && llm.length > 40 && !reportText.contains(llm.substring(0, 40))) {
            replyText = '$reportText\n\n$llm';
          }
        }
        final inspectionMsg = res['inspection_message'];
        if (inspectionMsg != null) {
          final merged = <AiChatAttachment>[];
          final seen = <String>{};
          for (final a in [...AiChatMessage.parseReply(inspectionMsg), ...attachments]) {
            final key = '${a.type}:${a.mediaId ?? a.url}';
            if (seen.add(key)) merged.add(a);
          }
          attachments = merged;
        }
      }
      if (replyText.isEmpty) replyText = res['text']?.toString() ?? 'Пустой ответ';
      if (!mounted) return;
      setState(() {
        _messages.add(
          AiChatMessage(
            role: 'assistant',
            text: replyText,
            attachments: attachments,
            quickReplies: quickReplies,
          ),
        );
      });
    } on BotApiException catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
      _scrollToEnd();
    }
  }

  Future<void> _toggleVoice() async {
    if (_loading) return;
    if (_recording) {
      final path = await _recorder.stop();
      setState(() => _recording = false);
      if (path == null || path.isEmpty) return;
      setState(() {
        _loading = true;
        _error = null;
      });
      try {
        final transcript = await BotApi(widget.session).transcribeFile(
          File(path),
          filename: 'voice.wav',
        );
        if (!mounted) return;
        if (transcript.isEmpty) {
          setState(() => _error = 'Не удалось распознать речь');
          return;
        }
        await _send(preset: transcript);
      } on BotApiException catch (e) {
        if (mounted) setState(() => _error = e.toString());
      } catch (e) {
        if (mounted) setState(() => _error = e.toString());
      } finally {
        if (mounted) setState(() => _loading = false);
      }
      return;
    }

    final ok = await _recorder.start();
    if (!mounted) return;
    if (!ok) {
      setState(() => _error = 'Нет доступа к микрофону');
      return;
    }
    setState(() {
      _recording = true;
      _error = null;
    });
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    });
  }

  List<Widget> _templateChips() {
    final order = widget.order;
    if (order != null && _apiTemplates.isNotEmpty) {
      return _apiTemplates
          .map(
            (t) => ActionChip(
              avatar: const Icon(Icons.warning_amber_outlined, size: 16),
              label: Text(t.label, style: const TextStyle(fontSize: 12)),
              onPressed: _loading ? null : () => _send(preset: t.displayMessage, templateId: t.id),
            ),
          )
          .toList();
    }
    if (order != null) {
      return _templatesCarLegacy
          .map(
            (t) => ActionChip(
              label: Text(t, style: const TextStyle(fontSize: 12)),
              onPressed: _loading ? null : () => _send(preset: t),
            ),
          )
          .toList();
    }
    return _templatesGeneral
        .map(
          (t) => ActionChip(
            label: Text(t, style: const TextStyle(fontSize: 12)),
            onPressed: _loading ? null : () => _send(preset: t),
          ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(order == null ? 'ИИ-чат' : (order.regNumber ?? 'ИИ-чат')),
      ),
      body: Column(
        children: [
          if (order != null)
            Material(
              color: theme.colorScheme.surfaceContainerHighest,
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.directions_car_outlined),
                title: Text(order.regNumber ?? order.saleNumber),
                subtitle: Text(order.carInfo),
              ),
            ),
          _SearchModeBar(
            hasCar: order != null,
            mode: _searchMode,
            onChanged: (mode) => setState(() => _searchMode = mode),
          ),
          if (_error != null)
            Material(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!),
              ),
            ),
          if (_recording)
            Material(
              color: theme.colorScheme.primaryContainer,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                child: Row(
                  children: [
                    Icon(Icons.mic, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Запись… нажмите микрофон ещё раз, чтобы отправить'),
                  ],
                ),
              ),
            ),
          Expanded(
            child: ListView(
              controller: _scroll,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              children: [
                _Header(theme: theme, hasCar: order != null),
                const SizedBox(height: 12),
                if (_messages.isEmpty) _EmptyHints(hasCar: order != null, hasWeakSpotTemplates: _apiTemplates.isNotEmpty),
                ..._messages.asMap().entries.expand((entry) {
                  final index = entry.key;
                  final m = entry.value;
                  final isLastAssistant =
                      !m.isUser && index == _messages.lastIndexWhere((x) => !x.isUser);
                  return [
                    AiMessageBubble(
                      message: m,
                      auth: _mediaAuth,
                      onOpenUrl: (url) => openExternalUrl(context, url),
                    ),
                    if (!m.isUser && m.quickReplies.isNotEmpty && isLastAssistant)
                      _QuickRepliesBar(
                        replies: m.quickReplies,
                        loading: _loading,
                        onTap: (qr) => _send(
                          preset: qr.message,
                          templateId: qr.templateId ?? 'weak_spots_followup',
                        ),
                      ),
                  ];
                }),
                if (_loading) const _LoadingRow(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _templateChips(),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _loading ? null : _toggleVoice,
                    icon: Icon(
                      _recording ? Icons.stop_circle_outlined : Icons.mic_none_outlined,
                      color: _recording ? Colors.red : null,
                    ),
                    tooltip: _recording ? 'Остановить и отправить' : 'Голосовой вопрос',
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      focusNode: _inputFocus,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _loading ? null : (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Вопрос по авто, осмотру или работам…',
                        filled: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _loading ? null : () => _send(),
                    icon: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send),
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

class _QuickRepliesBar extends StatelessWidget {
  const _QuickRepliesBar({
    required this.replies,
    required this.loading,
    required this.onTap,
  });

  final List<AiQuickReply> replies;
  final bool loading;
  final ValueChanged<AiQuickReply> onTap;

  @override
  Widget build(BuildContext context) {
    if (replies.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 10, top: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: replies
            .map(
              (qr) => ActionChip(
                avatar: const Icon(Icons.subdirectory_arrow_right, size: 16),
                label: Text(qr.label, style: const TextStyle(fontSize: 12)),
                onPressed: loading ? null : () => onTap(qr),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.theme, required this.hasCar});

  final ThemeData theme;
  final bool hasCar;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [theme.colorScheme.primary, theme.colorScheme.secondary],
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.auto_awesome, color: Colors.white, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ИИ-помощник',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(
                hasCar
                    ? 'Шаблоны «слабые места» + уточнения после ответа'
                    : 'Справочник и поиск по ремонту',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyHints extends StatelessWidget {
  const _EmptyHints({required this.hasCar, required this.hasWeakSpotTemplates});

  final bool hasCar;
  final bool hasWeakSpotTemplates;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Справочно: сверяйтесь с мануалом производителя.',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Text(
              hasCar && hasWeakSpotTemplates
                  ? 'Нажмите «Слабые места этого авто» — ИИ найдёт типичные проблемы модели в интернете и предложит уточнения (рулевое, подвеска…). Микрофон — голосовой вопрос.'
                  : hasCar
                      ? '«Авто» — данные по машине. «История» — фото осмотров. «Веб» — поиск в интернете.'
                      : 'Режим «Веб» — поиск видео, схем и статей.',
              style: const TextStyle(height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchModeBar extends StatelessWidget {
  const _SearchModeBar({
    required this.hasCar,
    required this.mode,
    required this.onChanged,
  });

  final bool hasCar;
  final AiSearchMode mode;
  final ValueChanged<AiSearchMode> onChanged;

  @override
  Widget build(BuildContext context) {
    if (!hasCar) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Chip(
            avatar: const Icon(Icons.language, size: 16),
            label: const Text('Поиск в интернете'),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: SegmentedButton<AiSearchMode>(
        segments: [
          if (hasCar)
            const ButtonSegment(
              value: AiSearchMode.car,
              label: Text('Авто', style: TextStyle(fontSize: 12)),
              icon: Icon(Icons.directions_car_outlined, size: 16),
            ),
          ButtonSegment(
            value: AiSearchMode.history,
            label: const Text('История', style: TextStyle(fontSize: 12)),
            icon: const Icon(Icons.photo_library_outlined, size: 16),
            enabled: hasCar,
          ),
          const ButtonSegment(
            value: AiSearchMode.web,
            label: Text('Веб', style: TextStyle(fontSize: 12)),
            icon: Icon(Icons.language, size: 16),
          ),
        ],
        selected: {mode == AiSearchMode.auto ? AiSearchMode.car : mode},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}

class _LoadingRow extends StatelessWidget {
  const _LoadingRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 10),
          Text('Готовлю ответ…'),
        ],
      ),
    );
  }
}
