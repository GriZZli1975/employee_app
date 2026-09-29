import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/bot_api.dart';
import '../../core/session.dart';
import '../../core/work_order.dart';
import '../../widgets/media_carousel.dart';
import '../../widgets/network_photo.dart';
import '../ai/ai_chat_models.dart';
import '../ai/ai_message_bubble.dart';

final _dateFmt = DateFormat('dd.MM.yyyy HH:mm');

String _formatDate(dynamic raw) {
  final dt = DateTime.tryParse(raw?.toString() ?? '');
  return dt == null ? '' : _dateFmt.format(dt.toLocal());
}

String _kindLabel(dynamic kind) => kind?.toString() == 'diagnostics' ? 'Диагностика' : 'Осмотр';

IconData _kindIcon(dynamic kind) =>
    kind?.toString() == 'diagnostics' ? Icons.build_circle_outlined : Icons.photo_camera_outlined;

/// История осмотров и диагностик по машине — прямо из базы, без ИИ.
class InspectionHistoryScreen extends StatefulWidget {
  const InspectionHistoryScreen({super.key, required this.session, required this.order});

  final EmployeeSession session;
  final StooxWorkOrder order;

  @override
  State<InspectionHistoryScreen> createState() => _InspectionHistoryScreenState();
}

class _InspectionHistoryScreenState extends State<InspectionHistoryScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  MediaAuth _auth = const MediaAuth();

  @override
  void initState() {
    super.initState();
    _future = _load();
    _loadAuth();
  }

  Future<void> _loadAuth() async {
    try {
      final api = BotApi(widget.session);
      final headers = await api.mediaAuthHeaders();
      final base = await api.baseUrl();
      if (mounted) setState(() => _auth = MediaAuth(botBase: base, headers: headers));
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> _load() {
    final o = widget.order;
    return BotApi(widget.session).fetchInspectionHistory(
      carId: o.carId,
      plate: o.regNumber,
      clientId: o.carId == null && (o.regNumber ?? '').isEmpty ? o.clientId : null,
    );
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    return Scaffold(
      appBar: AppBar(
        title: const Text('История осмотров'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(22),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              [order.regNumber, order.carInfo].where((s) => (s ?? '').isNotEmpty).join(' · '),
              style: const TextStyle(fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _Message(
              icon: Icons.cloud_off_outlined,
              text: 'Не удалось загрузить историю.\n${snap.error}',
              onRetry: _refresh,
            );
          }
          final items = snap.data ?? const [];
          if (items.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                children: const [
                  SizedBox(height: 120),
                  _Message(
                    icon: Icons.history_toggle_off,
                    text: 'По этой машине ещё нет сохранённых осмотров и диагностик.',
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _HistoryCard(
                item: items[i],
                auth: _auth,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => InspectionDetailScreen(
                      session: widget.session,
                      reportId: items[i]['report_id'].toString(),
                      auth: _auth,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.item, required this.auth, required this.onTap});

  final Map<String, dynamic> item;
  final MediaAuth auth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final works = (item['works'] is List) ? (item['works'] as List).map((e) => e.toString()).toList() : <String>[];
    final counts = item['media_counts'] is Map ? Map<String, dynamic>.from(item['media_counts'] as Map) : const {};
    final preview = item['preview_url']?.toString();
    final summary = item['summary']?.toString().trim() ?? '';
    final employee = item['employee_name']?.toString().trim() ?? '';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: preview != null && preview.isNotEmpty
                      ? NetworkPhoto(
                          url: preview,
                          previewUrl: preview,
                          auth: auth,
                          fit: BoxFit.cover,
                          placeholder: Icon(_kindIcon(item['kind'])),
                        )
                      : ColoredBox(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Icon(_kindIcon(item['kind']), size: 32),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          _kindLabel(item['kind']),
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        if (item['has_pdf'] == true)
                          const Padding(
                            padding: EdgeInsets.only(right: 6),
                            child: Icon(Icons.picture_as_pdf_outlined, size: 18, color: Colors.redAccent),
                          ),
                        Text(_formatDate(item['completed_at']), style: theme.textTheme.bodySmall),
                      ],
                    ),
                    if (employee.isNotEmpty)
                      Text(employee, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                    if (summary.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(summary, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                    if (works.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Работы: ${works.take(3).join(', ')}${works.length > 3 ? ' +${works.length - 3}' : ''}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 6),
                    _CountsRow(counts: counts),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountsRow extends StatelessWidget {
  const _CountsRow({required this.counts});

  final Map<dynamic, dynamic> counts;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    Widget chip(IconData icon, dynamic n) {
      final v = int.tryParse('${n ?? 0}') ?? 0;
      if (v == 0) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15),
          const SizedBox(width: 3),
          Text('$v', style: style),
        ]),
      );
    }

    return Row(children: [
      chip(Icons.photo_outlined, counts['photo']),
      chip(Icons.videocam_outlined, counts['video']),
      chip(Icons.mic_none_outlined, counts['voice']),
    ]);
  }
}

class InspectionDetailScreen extends StatefulWidget {
  const InspectionDetailScreen({
    super.key,
    required this.session,
    required this.reportId,
    required this.auth,
  });

  final EmployeeSession session;
  final String reportId;
  final MediaAuth auth;

  @override
  State<InspectionDetailScreen> createState() => _InspectionDetailScreenState();
}

class _InspectionDetailScreenState extends State<InspectionDetailScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = BotApi(widget.session).fetchInspectionDetail(widget.reportId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        final item = snap.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(item == null
                ? 'Осмотр'
                : '${_kindLabel(item['kind'])} · ${_formatDate(item['completed_at'])}'),
          ),
          body: switch (snap.connectionState) {
            ConnectionState.done when snap.hasError => _Message(
                icon: Icons.cloud_off_outlined,
                text: 'Не удалось загрузить осмотр.\n${snap.error}',
                onRetry: () async {
                  setState(() => _future = BotApi(widget.session).fetchInspectionDetail(widget.reportId));
                },
              ),
            ConnectionState.done => _DetailBody(item: item ?? const {}, auth: widget.auth),
            _ => const Center(child: CircularProgressIndicator()),
          },
        );
      },
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.item, required this.auth});

  final Map<String, dynamic> item;
  final MediaAuth auth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = AiChatMessage.parseAttachments(item['media']);
    final photos = media.where((a) => a.isPhoto).toList();
    final photoItems = photos
        .map((p) => MediaCarouselItem(label: 'Фото', url: p.url, previewUrl: p.previewUrl, mediaId: p.mediaId))
        .toList();
    final voiceAndVideo = media.where((a) => a.isVoice || a.isVideo).toList();
    final works = (item['works'] is List)
        ? (item['works'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    final usedInWorks = <String>{
      for (final w in works)
        if (w['media_ids'] is List) ...(w['media_ids'] as List).map((e) => e.toString()),
    };
    final loosePhotos = photos.where((p) => !usedInWorks.contains(p.mediaId)).toList();
    final summary = item['summary']?.toString().trim() ?? '';
    final transcript = item['transcript']?.toString().trim() ?? '';
    final employee = item['employee_name']?.toString().trim() ?? '';
    final pdfUrl = item['pdf_url']?.toString();

    void openPhoto(AiChatAttachment p) {
      final index = photos.indexOf(p);
      openMediaCarousel(context, items: photoItems, initialIndex: index < 0 ? 0 : index, auth: auth);
    }

    Widget thumbs(List<AiChatAttachment> list) => Wrap(
          spacing: 6,
          runSpacing: 6,
          children: list
              .map(
                (p) => GestureDetector(
                  onTap: () => openPhoto(p),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: NetworkPhoto(
                      url: p.url,
                      previewUrl: p.previewUrl,
                      mediaId: p.mediaId,
                      auth: auth,
                      width: 92,
                      height: 92,
                      fit: BoxFit.cover,
                      placeholder: const Icon(Icons.image_outlined),
                    ),
                  ),
                ),
              )
              .toList(),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        if (employee.isNotEmpty)
          Text('Выполнил: $employee', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
        if (pdfUrl != null && pdfUrl.isNotEmpty) ...[
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () => openExternalUrl(context, pdfUrl),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Открыть PDF для клиента'),
          ),
        ],
        if (summary.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Итог', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(summary, style: const TextStyle(height: 1.4)),
        ],
        if (works.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Рекомендованные работы (${works.length})', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          ...works.map((w) {
            final ids = (w['media_ids'] is List) ? (w['media_ids'] as List).map((e) => e.toString()).toSet() : <String>{};
            final workPhotos = photos.where((p) => ids.contains(p.mediaId)).toList();
            final defect = w['defect']?.toString().trim() ?? '';
            final description = w['description']?.toString().trim() ?? '';
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(w['title']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (defect.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(defect, style: TextStyle(color: theme.colorScheme.error)),
                    ],
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(description, style: const TextStyle(height: 1.35)),
                    ],
                    if (workPhotos.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      thumbs(workPhotos),
                    ],
                  ],
                ),
              ),
            );
          }),
        ],
        if (loosePhotos.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(works.isEmpty ? 'Фото (${loosePhotos.length})' : 'Остальные фото (${loosePhotos.length})',
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          thumbs(loosePhotos),
        ],
        if (voiceAndVideo.isNotEmpty) ...[
          const SizedBox(height: 16),
          AiMessageBubble(
            message: AiChatMessage(
              role: 'assistant',
              text: 'Голос и видео (${voiceAndVideo.length})',
              attachments: voiceAndVideo,
            ),
            auth: auth,
            onOpenUrl: (url) => openExternalUrl(context, url),
          ),
        ],
        if (transcript.isNotEmpty) ...[
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Расшифровка голоса'),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(transcript, style: const TextStyle(height: 1.4)),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.onRetry});

  final IconData icon;
  final String text;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onRetry, child: const Text('Повторить')),
            ],
          ],
        ),
      ),
    );
  }
}
