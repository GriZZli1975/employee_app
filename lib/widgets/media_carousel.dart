import 'dart:io';

import 'package:flutter/material.dart';

import 'network_photo.dart';

class MediaCarouselItem {
  const MediaCarouselItem({
    required this.label,
    this.filePath,
    this.url,
    this.previewUrl,
    this.mediaId,
  });

  final String label;
  final String? filePath;
  final String? url;
  final String? previewUrl;
  final String? mediaId;
}

Future<void> openMediaCarousel(
  BuildContext context, {
  required List<MediaCarouselItem> items,
  int initialIndex = 0,
  MediaAuth? auth,
}) {
  if (items.isEmpty) return Future.value();
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => MediaCarouselScreen(items: items, initialIndex: initialIndex, auth: auth),
    ),
  );
}

class MediaCarouselScreen extends StatefulWidget {
  const MediaCarouselScreen({
    super.key,
    required this.items,
    this.initialIndex = 0,
    this.auth,
  });

  final List<MediaCarouselItem> items;
  final int initialIndex;
  final MediaAuth? auth;

  @override
  State<MediaCarouselScreen> createState() => _MediaCarouselScreenState();
}

class _MediaCarouselScreenState extends State<MediaCarouselScreen> {
  late final PageController _page;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.items.length - 1);
    _page = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.items[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          tooltip: 'Закрыть',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.items.length > 1
              ? '${item.label}  ${_index + 1}/${widget.items.length}'
              : item.label,
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _page,
              itemCount: widget.items.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) {
                return InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 5,
                  child: SizedBox.expand(child: _image(widget.items[i])),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Закрыть'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _image(MediaCarouselItem item) {
    if (item.filePath != null && File(item.filePath!).existsSync()) {
      return Image.file(File(item.filePath!), fit: BoxFit.contain);
    }
    return NetworkPhoto(
      url: item.url,
      previewUrl: item.previewUrl,
      mediaId: item.mediaId,
      auth: widget.auth,
      fit: BoxFit.contain,
      preferFull: true,
      placeholder: const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64),
    );
  }
}
