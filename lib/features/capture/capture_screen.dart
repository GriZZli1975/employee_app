import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/bot_api.dart';
import '../../core/session.dart';
import '../../core/work_order.dart';
import '../../widgets/media_carousel.dart';
import 'burst_camera_screen.dart';
import 'voice_recorder.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({
    super.key,
    required this.session,
    required this.order,
    required this.kind,
    required this.title,
    this.employeeId,
    this.employeeName,
  });

  final EmployeeSession session;
  final StooxWorkOrder order;
  final String kind;
  final String title;
  final int? employeeId;
  final String? employeeName;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _SessionItem {
  _SessionItem({
    required this.id,
    required this.label,
    required this.messageType,
    required this.filePath,
    this.mediaId,
    this.previewUrl,
    this.failed = false,
  });

  final String id;
  final String label;
  final String messageType;
  final String filePath;
  String? mediaId;
  String? previewUrl;
  bool failed;

  bool get isPhoto => messageType == 'photo';
}

class _DraftResult {
  _DraftResult({
    required this.summary,
    required this.transcript,
    required this.workItems,
    required this.transcriptionOk,
  });

  String summary;
  String transcript;
  List<String> workItems;
  final bool transcriptionOk;
}

class _CaptureScreenState extends State<CaptureScreen> {
  final _picker = ImagePicker();
  final _voice = VoiceRecorder();
  final _notesCtrl = TextEditingController();
  final _items = <_SessionItem>[];
  late String _sessionId;
  bool _finishing = false;
  bool _recording = false;
  DateTime? _recordStarted;
  Timer? _recordTick;
  String? _error;
  _DraftResult? _draft;
  final _workCtrls = <TextEditingController>[];
  final _transcriptCtrl = TextEditingController();
  int _pendingUploads = 0;

  BotApi get _bot => BotApi(widget.session);

  @override
  void initState() {
    super.initState();
    _sessionId = 'sess_${DateTime.now().millisecondsSinceEpoch}';
    _restoreDraft();
  }

  @override
  void dispose() {
    _recordTick?.cancel();
    _notesCtrl.dispose();
    _transcriptCtrl.dispose();
    for (final c in _workCtrls) {
      c.dispose();
    }
    _voice.dispose();
    super.dispose();
  }

  Future<void> _restoreDraft() async {
    final data = await widget.session.loadCaptureDraft(
      kind: widget.kind,
      carId: widget.order.carId,
      plate: widget.order.regNumber,
    );
    if (data == null || !mounted) return;
    final sid = data['session_id']?.toString();
    if (sid != null && sid.isNotEmpty) _sessionId = sid;
    _notesCtrl.text = data['notes']?.toString() ?? '';
    final rawItems = data['items'];
    if (rawItems is List) {
      for (final raw in rawItems) {
        if (raw is! Map) continue;
        final path = raw['filePath']?.toString() ?? '';
        if (path.isEmpty || !File(path).existsSync()) continue;
        _items.add(
          _SessionItem(
            id: raw['id']?.toString() ?? UniqueKey().toString(),
            label: raw['label']?.toString() ?? 'Файл',
            messageType: raw['messageType']?.toString() ?? 'photo',
            filePath: path,
            mediaId: raw['mediaId']?.toString(),
            previewUrl: raw['previewUrl']?.toString(),
            failed: raw['failed'] == true,
          ),
        );
      }
    }
    setState(() {});
    for (final item in List<_SessionItem>.from(_items)) {
      if ((item.mediaId == null || item.mediaId!.isEmpty) && !item.failed) {
        unawaited(_uploadItem(item));
      }
    }
  }

  Future<void> _persistDraft() async {
    await widget.session.saveCaptureDraft(
      kind: widget.kind,
      carId: widget.order.carId,
      plate: widget.order.regNumber,
      draft: {
        'session_id': _sessionId,
        'notes': _notesCtrl.text,
        'items': _items
            .map(
              (e) => {
                'id': e.id,
                'label': e.label,
                'messageType': e.messageType,
                'filePath': e.filePath,
                'mediaId': e.mediaId,
                'previewUrl': e.previewUrl,
                'failed': e.failed,
              },
            )
            .toList(),
      },
    );
  }

  void _enqueueFile({
    required File file,
    required String messageType,
    required String filename,
    required String mimeType,
    required String label,
  }) {
    final item = _SessionItem(
      id: UniqueKey().toString(),
      label: label,
      messageType: messageType,
      filePath: file.path,
    );
    setState(() {
      _items.insert(0, item);
      _error = null;
    });
    unawaited(_persistDraft());
    unawaited(_uploadItem(item, filename: filename, mimeType: mimeType));
  }

  Future<void> _uploadItem(_SessionItem item, {String? filename, String? mimeType}) async {
    setState(() => _pendingUploads++);
    try {
      final ext = item.filePath.split('.').last.toLowerCase();
      final res = await _bot.uploadFile(
        file: File(item.filePath),
        kind: widget.kind,
        messageType: item.messageType,
        filename: filename ?? 'file.$ext',
        mimeType: mimeType ?? _mimeFor(item.messageType, ext),
        order: widget.order,
        sessionId: _sessionId,
        employeeId: widget.employeeId,
      );
      item.mediaId = res['media_id']?.toString() ?? res['file_id']?.toString();
      item.previewUrl = res['preview_url']?.toString();
      item.failed = false;
    } catch (_) {
      item.failed = true;
    } finally {
      if (mounted) {
        setState(() => _pendingUploads = (_pendingUploads - 1).clamp(0, 999));
        unawaited(_persistDraft());
      }
    }
  }

  String _mimeFor(String type, String ext) {
    if (type == 'photo') return 'image/jpeg';
    if (type == 'video') return 'video/mp4';
    if (ext == 'wav') return 'audio/wav';
    if (ext == 'm4a') return 'audio/mp4';
    return 'application/octet-stream';
  }

  Future<void> _openBurstCamera() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BurstCameraScreen(
          onCaptured: (file) async {
            _enqueueFile(
              file: file,
              messageType: 'photo',
              filename: 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg',
              mimeType: 'image/jpeg',
              label: 'Фото',
            );
          },
        ),
      ),
    );
  }

  Future<void> _pickGallery() async {
    final files = await _picker.pickMultiImage(imageQuality: 70, maxWidth: 1920, maxHeight: 1920);
    for (final file in files) {
      _enqueueFile(
        file: File(file.path),
        messageType: 'photo',
        filename: file.name.isNotEmpty ? file.name : 'photo.jpg',
        mimeType: 'image/jpeg',
        label: 'Фото',
      );
    }
  }

  Future<void> _pickVideo() async {
    final file = await _picker.pickVideo(source: ImageSource.camera, maxDuration: const Duration(minutes: 2));
    if (file == null) return;
    _enqueueFile(
      file: File(file.path),
      messageType: 'video',
      filename: file.name.isNotEmpty ? file.name : 'video.mp4',
      mimeType: 'video/mp4',
      label: 'Видео',
    );
  }

  Future<void> _startVoice() async {
    if (_recording) return;
    final ok = await _voice.start();
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет доступа к микрофону')),
        );
      }
      return;
    }
    setState(() {
      _recording = true;
      _recordStarted = DateTime.now();
    });
    _recordTick?.cancel();
    _recordTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _stopVoice() async {
    if (!_recording) return;
    _recordTick?.cancel();
    final path = await _voice.stop();
    setState(() {
      _recording = false;
      _recordStarted = null;
    });
    if (path == null) return;
    _enqueueFile(
      file: File(path),
      messageType: 'voice',
      filename: 'voice.wav',
      mimeType: 'audio/wav',
      label: 'Голос',
    );
  }

  String _recordLabel() {
    final start = _recordStarted;
    if (start == null) return '0:00';
    final s = DateTime.now().difference(start).inSeconds;
    final m = (s ~/ 60).toString();
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$m:$ss';
  }

  Future<void> _removeItem(_SessionItem item) async {
    setState(() => _items.remove(item));
    await _persistDraft();
  }

  List<MediaCarouselItem> get _photoCarousel => _items
      .where((e) => e.isPhoto)
      .map((e) => MediaCarouselItem(label: e.label, filePath: e.filePath, url: e.previewUrl))
      .toList();

  Future<void> _prepareDraft() async {
    if (_finishing) return;
    if (_recording) await _stopVoice();
    if (_items.isEmpty && _notesCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Снимите фото, наговорите или напишите комментарий.');
      return;
    }
    setState(() {
      _finishing = true;
      _error = null;
    });
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    while (_pendingUploads > 0 && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    try {
      final res = await _bot.completeInspection(
        sessionId: _sessionId,
        kind: widget.kind,
        order: widget.order,
        employeeId: widget.employeeId,
        employeeName: widget.employeeName,
        notes: _notesCtrl.text.trim(),
        notifyMp: false,
      );
      if (!mounted) return;
      final works = (res['work_items'] is List)
          ? (res['work_items'] as List).map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList()
          : <String>[];
      for (final c in _workCtrls) {
        c.dispose();
      }
      _workCtrls
        ..clear()
        ..addAll(works.map((w) => TextEditingController(text: w)));
      _transcriptCtrl.text = res['transcript']?.toString() ?? _notesCtrl.text;
      setState(() {
        _draft = _DraftResult(
          summary: res['summary']?.toString() ?? '',
          transcript: _transcriptCtrl.text,
          workItems: works,
          transcriptionOk: res['transcription_ok'] != false,
        );
      });
    } on BotApiException catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } catch (e) {
      if (mounted) setState(() => _error = 'Не удалось подготовить черновик.\n$e');
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  Future<void> _sendToMp() async {
    if (_finishing || _draft == null) return;
    setState(() => _finishing = true);
    try {
      final works = _workCtrls.map((c) => c.text.trim()).where((e) => e.isNotEmpty).toList();
      await _bot.completeInspection(
        sessionId: _sessionId,
        kind: widget.kind,
        order: widget.order,
        employeeId: widget.employeeId,
        employeeName: widget.employeeName,
        notes: _notesCtrl.text.trim(),
        transcript: _transcriptCtrl.text.trim(),
        workItems: works,
        notifyMp: true,
      );
      await widget.session.clearCaptureDraft(
        kind: widget.kind,
        carId: widget.order.carId,
        plate: widget.order.regNumber,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Отправлено мастеру-приёмщику')),
      );
      Navigator.of(context).pop();
    } on BotApiException catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } catch (e) {
      if (mounted) setState(() => _error = 'Не удалось отправить МП.\n$e');
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  Future<void> _discardDraft() async {
    await widget.session.clearCaptureDraft(
      kind: widget.kind,
      carId: widget.order.carId,
      plate: widget.order.regNumber,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) unawaited(_persistDraft());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            TextButton(
              onPressed: _discardDraft,
              child: const Text('Сбросить'),
            ),
          ],
        ),
        body: draft != null ? _buildDraft(context, draft) : _buildCapture(context),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton.icon(
              onPressed: _finishing
                  ? null
                  : draft != null
                      ? _sendToMp
                      : _prepareDraft,
              icon: Icon(draft != null ? Icons.send : Icons.check),
              label: Text(
                _finishing
                    ? 'Секунду…'
                    : draft != null
                        ? 'Отправить МП'
                        : 'Готово',
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCapture(BuildContext context) {
    final order = widget.order;
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text(
          order.regNumber ?? order.saleNumber,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        if (order.carInfo.isNotEmpty)
          Text(order.carInfo, style: TextStyle(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 12),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_error!, style: TextStyle(color: scheme.error)),
          ),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _openBurstCamera,
                icon: const Icon(Icons.photo_camera),
                label: const Text('Камера'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Галерея',
              onPressed: _pickGallery,
              icon: const Icon(Icons.photo_library_outlined),
            ),
            IconButton.filledTonal(
              tooltip: 'Видео',
              onPressed: _pickVideo,
              icon: const Icon(Icons.videocam_outlined),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Center(
          child: Column(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (_) => _startVoice(),
                onTapUp: (_) => _stopVoice(),
                onTapCancel: _stopVoice,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _recording ? scheme.error : scheme.primary,
                    boxShadow: [
                      BoxShadow(
                        color: (_recording ? scheme.error : scheme.primary).withValues(alpha: 0.35),
                        blurRadius: _recording ? 18 : 8,
                      ),
                    ],
                  ),
                  child: Icon(_recording ? Icons.stop : Icons.mic, color: scheme.onPrimary, size: 40),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _recording ? 'Говорите · ${_recordLabel()}' : 'Зажмите и говорите',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _notesCtrl,
          minLines: 2,
          maxLines: 5,
          onChanged: (_) => unawaited(_persistDraft()),
          decoration: const InputDecoration(
            labelText: 'Комментарий текстом',
            hintText: 'Можно написать, если не хочется диктовать',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        Text('Снято', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_items.isEmpty)
          Text('Пока пусто — снимайте, не дожидаясь загрузки.', style: TextStyle(color: scheme.onSurfaceVariant))
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _items.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemBuilder: (context, i) {
              final item = _items[i];
              final photos = _photoCarousel;
              final photoIndex = photos.indexWhere((p) => p.filePath == item.filePath);
              return Dismissible(
                key: ValueKey(item.id),
                direction: DismissDirection.up,
                onDismissed: (_) => _removeItem(item),
                child: GestureDetector(
                  onTap: () {
                    if (item.failed) {
                      unawaited(_uploadItem(item));
                      return;
                    }
                    if (item.isPhoto && photoIndex >= 0) {
                      openMediaCarousel(context, items: photos, initialIndex: photoIndex);
                    }
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (item.isPhoto && File(item.filePath).existsSync())
                          Image.file(File(item.filePath), fit: BoxFit.cover)
                        else
                          ColoredBox(
                            color: scheme.surfaceContainerHighest,
                            child: Icon(
                              item.messageType == 'voice' ? Icons.mic : Icons.videocam,
                              color: scheme.primary,
                            ),
                          ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: InkWell(
                            onTap: () => _removeItem(item),
                            child: const CircleAvatar(
                              radius: 12,
                              backgroundColor: Colors.black54,
                              child: Icon(Icons.close, size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                        if (item.failed)
                          const ColoredBox(
                            color: Color(0x66000000),
                            child: Icon(Icons.error_outline, color: Colors.white),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildDraft(BuildContext context, _DraftResult draft) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text('Проверьте перед отправкой МП', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (!draft.transcriptionOk)
          Text(
            'Голос мог не расшифроваться — поправьте текст ниже.',
            style: TextStyle(color: scheme.error),
          ),
        const SizedBox(height: 8),
        TextField(
          controller: _transcriptCtrl,
          minLines: 4,
          maxLines: 10,
          decoration: const InputDecoration(
            labelText: 'Что наговорил / написал исполнитель',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text('Работы', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            TextButton.icon(
              onPressed: () => setState(() => _workCtrls.add(TextEditingController())),
              icon: const Icon(Icons.add),
              label: const Text('Строка'),
            ),
          ],
        ),
        ..._workCtrls.asMap().entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: e.value,
                  decoration: InputDecoration(
                    prefixText: '${e.key + 1}. ',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () {
                        setState(() {
                          _workCtrls.removeAt(e.key).dispose();
                        });
                      },
                    ),
                  ),
                ),
              ),
            ),
        if (_photoCarousel.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Фото', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SizedBox(
            height: 88,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _photoCarousel.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final p = _photoCarousel[i];
                return GestureDetector(
                  onTap: () => openMediaCarousel(context, items: _photoCarousel, initialIndex: i),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: p.filePath != null && File(p.filePath!).existsSync()
                        ? Image.file(File(p.filePath!), width: 88, height: 88, fit: BoxFit.cover)
                        : const SizedBox(width: 88, height: 88, child: Icon(Icons.image)),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}
