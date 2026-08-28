import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';

import 'ai_chat_models.dart';

class AiMessageBubble extends StatelessWidget {
  const AiMessageBubble({
    super.key,
    required this.message,
    required this.onOpenUrl,
  });

  final AiChatMessage message;
  final Future<void> Function(String? url) onOpenUrl;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final align = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bg = isUser
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceContainerHighest;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.88),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(14),
                topRight: const Radius.circular(14),
                bottomLeft: Radius.circular(isUser ? 14 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 14),
              ),
            ),
            child: _RichMessageText(text: message.text, onLinkTap: onOpenUrl),
          ),
          if (!isUser && message.images.isNotEmpty) ...[
            const SizedBox(height: 8),
            _ImagesRow(images: message.images, onOpen: onOpenUrl),
          ],
          if (!isUser && message.videos.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...message.videos.map((v) => _VideoTile(video: v, onOpen: onOpenUrl)),
          ],
          if (!isUser && message.voices.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...message.voices.map((v) => _VoiceTile(attachment: v, onOpenUrl: onOpenUrl)),
          ],
          if (!isUser && message.sources.isNotEmpty) ...[
            const SizedBox(height: 8),
            _SourcesList(sources: message.sources, onOpen: onOpenUrl),
          ],
        ],
      ),
    );
  }
}

class _RichMessageText extends StatelessWidget {
  const _RichMessageText({required this.text, required this.onLinkTap});

  final String text;
  final Future<void> Function(String? url) onLinkTap;

  static final _urlRe = RegExp(r'https?://[^\s\]\)<>"]+', caseSensitive: false);
  static final _mdLinkRe = RegExp(r'\[([^\]]+)\]\((https?://[^)]+)\)');
  static final _mdImageRe = RegExp(r'!\[[^\]]*\]\([^)]+\)');

  @override
  Widget build(BuildContext context) {
    var cleaned = text.replaceAll(_mdImageRe, '').trim();
    cleaned = cleaned.replaceAll(RegExp(r'^---\s*$', multiLine: true), '');
    cleaned = cleaned.replaceAll(RegExp(r'^\*\*Изображения:\*\*\s*$', multiLine: true), '');
    cleaned = cleaned.replaceAll(RegExp(r'^\*\*Аудио:\*\*\s*$', multiLine: true), '');
    cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    if (cleaned.isEmpty) return const SizedBox.shrink();

    final spans = <InlineSpan>[];
    var rest = cleaned;
    while (rest.isNotEmpty) {
      final md = _mdLinkRe.firstMatch(rest);
      if (md != null && md.start == 0) {
        spans.add(_linkSpan(md.group(1) ?? 'Ссылка', md.group(2)!));
        rest = rest.substring(md.end);
        continue;
      }
      if (md != null && md.start > 0) {
        spans.addAll(_plainSpans(rest.substring(0, md.start)));
        rest = rest.substring(md.start);
        continue;
      }
      spans.addAll(_plainSpans(rest));
      break;
    }

    return SelectableText.rich(TextSpan(style: const TextStyle(height: 1.4), children: spans));
  }

  List<InlineSpan> _plainSpans(String chunk) {
    final spans = <InlineSpan>[];
    var rest = chunk;
    while (rest.isNotEmpty) {
      final m = _urlRe.firstMatch(rest);
      if (m == null) {
        spans.add(TextSpan(text: rest));
        break;
      }
      if (m.start > 0) spans.add(TextSpan(text: rest.substring(0, m.start)));
      final url = m.group(0)!;
      spans.add(_linkSpan(url, url));
      rest = rest.substring(m.end);
    }
    return spans;
  }

  TextSpan _linkSpan(String label, String url) {
    return TextSpan(
      text: label,
      style: const TextStyle(color: Colors.blue, decoration: TextDecoration.underline),
      recognizer: TapGestureRecognizer()..onTap = () => onLinkTap(url),
    );
  }
}

class _ImagesRow extends StatelessWidget {
  const _ImagesRow({required this.images, required this.onOpen});

  final List<Map<String, dynamic>> images;
  final Future<void> Function(String? url) onOpen;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 108,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final img = images[i];
          final thumb = (img['thumbnail'] ?? img['url'] ?? '').toString();
          final url = (img['url'] ?? thumb).toString();
          final title = (img['title'] ?? 'Фото').toString();
          return GestureDetector(
            onTap: () => _openPhotoViewer(context, url, title, onOpen),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: thumb.isNotEmpty
                      ? Image.network(
                          thumb,
                          width: 120,
                          height: 88,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _imagePlaceholder(),
                        )
                      : _imagePlaceholder(),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: 120,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      width: 120,
      height: 88,
      color: Colors.black12,
      child: const Icon(Icons.broken_image_outlined),
    );
  }

  void _openPhotoViewer(
    BuildContext context,
    String url,
    String title,
    Future<void> Function(String? url) onOpen,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        child: Stack(
          children: [
            InteractiveViewer(
              child: Center(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, size: 64),
                ),
              ),
            ),
            SafeArea(
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                  Expanded(
                    child: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.open_in_new, color: Colors.white),
                    onPressed: () => onOpen(url),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoTile extends StatelessWidget {
  const _VideoTile({required this.video, required this.onOpen});

  final Map<String, dynamic> video;
  final Future<void> Function(String? url) onOpen;

  @override
  Widget build(BuildContext context) {
    final title = (video['title'] ?? 'Видео').toString();
    final url = video['url']?.toString();
    final channel = (video['channel'] ?? '').toString();
    final duration = (video['duration'] ?? '').toString();
    final thumb = (video['thumbnail'] ?? '').toString();
    final meta = [channel, duration].where((s) => s.isNotEmpty).join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () => onOpen(url),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              if (thumb.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    thumb,
                    width: 88,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(
                      width: 88,
                      height: 56,
                      child: ColoredBox(color: Colors.black12),
                    ),
                  ),
                )
              else
                const SizedBox(
                  width: 88,
                  height: 56,
                  child: ColoredBox(
                    color: Colors.black12,
                    child: Icon(Icons.play_circle_outline),
                  ),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (meta.isNotEmpty)
                      Text(meta, style: const TextStyle(fontSize: 11, color: Colors.black54)),
                  ],
                ),
              ),
              const Icon(Icons.open_in_new, size: 18, color: Colors.black45),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourcesList extends StatelessWidget {
  const _SourcesList({required this.sources, required this.onOpen});

  final List<Map<String, dynamic>> sources;
  final Future<void> Function(String? url) onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.92),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Источники', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 6),
          ...sources.take(6).map(
                (s) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: InkWell(
                    onTap: () => onOpen(s['url']?.toString()),
                    child: Text(
                      '• ${s['title'] ?? s['url'] ?? ''}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.primary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _VoiceTile extends StatefulWidget {
  const _VoiceTile({required this.attachment, required this.onOpenUrl});

  final AiChatAttachment attachment;
  final Future<void> Function(String? url) onOpenUrl;

  @override
  State<_VoiceTile> createState() => _VoiceTileState();
}

class _VoiceTileState extends State<_VoiceTile> {
  late final AudioPlayer _player;
  bool _loading = false;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() => _playing = state.playing);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      return;
    }
    setState(() => _loading = true);
    try {
      if (_player.processingState == ProcessingState.idle) {
        await _player.setUrl(widget.attachment.url);
      }
      await _player.play();
    } catch (_) {
      await widget.onOpenUrl(widget.attachment.url);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
          child: _loading
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(_playing ? Icons.pause : Icons.play_arrow, color: Theme.of(context).colorScheme.primary),
        ),
        title: Text(widget.attachment.displayTitle),
        subtitle: Text(_playing ? 'Воспроизведение…' : 'Нажмите для прослушивания'),
        trailing: IconButton(
          icon: const Icon(Icons.open_in_new),
          onPressed: () => widget.onOpenUrl(widget.attachment.url),
        ),
        onTap: _loading ? null : _toggle,
      ),
    );
  }
}

Future<void> openExternalUrl(BuildContext context, String? raw) async {
  final url = (raw ?? '').trim();
  if (url.isEmpty) return;
  final uri = Uri.tryParse(url);
  if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть ссылку')),
      );
    }
  }
}
