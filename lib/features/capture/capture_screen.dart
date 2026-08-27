import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/bot_api.dart';
import '../../core/session.dart';
import '../../core/work_order.dart';
import '../ai/ai_chat_screen.dart';
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

class _UploadedItem {
  _UploadedItem({
    required this.label,
    required this.mediaId,
    this.previewUrl,
  });

  final String label;
  final String mediaId;
  final String? previewUrl;
}

class _CaptureScreenState extends State<CaptureScreen> {
  final _picker = ImagePicker();
  final _voice = VoiceRecorder();
  final _sessionId = 'sess_${DateTime.now().millisecondsSinceEpoch}';
  final _items = <_UploadedItem>[];
  bool _busy = false;
  bool _recording = false;
  String? _error;

  BotApi get _bot => BotApi(widget.session);

  @override
  void dispose() {
    _voice.dispose();
    super.dispose();
  }

  Future<void> _upload({
    required File file,
    required String messageType,
    required String filename,
    required String mimeType,
    required String label,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await _bot.uploadFile(
        file: file,
        kind: widget.kind,
        messageType: messageType,
        filename: filename,
        mimeType: mimeType,
        order: widget.order,
        sessionId: _sessionId,
        employeeId: widget.employeeId,
      );
      final id = res['media_id']?.toString() ?? res['file_id']?.toString() ?? '';
      if (!mounted) return;
      setState(() {
        _items.insert(
          0,
          _UploadedItem(
            label: label,
            mediaId: id,
            previewUrl: res['preview_url']?.toString(),
          ),
        );
      });
    } on BotApiException catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final file = await _picker.pickImage(source: source, imageQuality: 85);
    if (file == null) return;
    await _upload(
      file: File(file.path),
      messageType: 'photo',
      filename: file.name.isNotEmpty ? file.name : 'photo.jpg',
      mimeType: 'image/jpeg',
      label: source == ImageSource.camera ? 'Фото с камеры' : 'Фото из галереи',
    );
  }

  Future<void> _pickVideo(ImageSource source) async {
    final file = await _picker.pickVideo(source: source, maxDuration: const Duration(minutes: 2));
    if (file == null) return;
    await _upload(
      file: File(file.path),
      messageType: 'video',
      filename: file.name.isNotEmpty ? file.name : 'video.mp4',
      mimeType: 'video/mp4',
      label: 'Видео',
    );
  }

  Future<void> _toggleVoice() async {
    if (_recording) {
      final path = await _voice.stop();
      setState(() => _recording = false);
      if (path == null) return;
      await _upload(
        file: File(path),
        messageType: 'voice',
        filename: 'voice.wav',
        mimeType: 'audio/wav',
        label: 'Голос',
      );
      return;
    }
    final ok = await _voice.start();
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет доступа к микрофону')),
        );
      }
      return;
    }
    setState(() => _recording = true);
  }

  void _openAi() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AiChatScreen(
          session: widget.session,
          order: widget.order,
          employeeId: widget.employeeId,
          employeeName: widget.employeeName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'ИИ-чат',
            onPressed: _openAi,
            icon: const Icon(Icons.smart_toy_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            order.regNumber ?? order.saleNumber,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          if (order.carInfo.isNotEmpty)
            Text(order.carInfo, style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 8),
          const Text(
            'Каждый файл сразу уходит в Yandex через бота. Секрет webhook на телефоне не нужен.',
            style: TextStyle(color: Colors.black54, height: 1.35),
          ),
          const SizedBox(height: 16),
          if (_busy) const LinearProgressIndicator(minHeight: 3),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Material(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.photo_camera),
                label: const Text('Камера'),
              ),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Галерея'),
              ),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : () => _pickVideo(ImageSource.camera),
                icon: const Icon(Icons.videocam_outlined),
                label: const Text('Видео'),
              ),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _toggleVoice,
                icon: Icon(_recording ? Icons.stop : Icons.mic_none),
                label: Text(_recording ? 'Стоп' : 'Голос'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('В этой сессии', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_items.isEmpty)
            const Text(
              'Пока ничего не снято.',
              style: TextStyle(color: Colors.black54),
            )
          else
            ..._items.map(
              (item) => Card(
                child: ListTile(
                  leading: item.previewUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            item.previewUrl!,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Icon(Icons.check_circle_outline),
                          ),
                        )
                      : const Icon(Icons.check_circle_outline),
                  title: Text(item.label),
                  subtitle: Text(
                    item.mediaId.isEmpty ? 'загружено' : item.mediaId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
