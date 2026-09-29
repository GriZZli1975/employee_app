import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class MediaAuth {
  const MediaAuth({this.botBase, this.headers = const {}});

  final String? botBase;
  final Map<String, String> headers;

  bool get canProxy => (botBase ?? '').isNotEmpty && headers.isNotEmpty;

  String? proxyUrl(String mediaId, {bool preview = false}) {
    final base = botBase;
    if (base == null || base.isEmpty) return null;
    final q = preview ? '?preview=1' : '';
    return '$base/api/media/$mediaId/file$q';
  }
}

class NetworkPhoto extends StatelessWidget {
  const NetworkPhoto({
    super.key,
    this.url,
    this.previewUrl,
    this.mediaId,
    this.auth,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.preferFull = false,
  });

  final String? url;
  final String? previewUrl;
  final String? mediaId;
  final MediaAuth? auth;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final bool preferFull;

  @override
  Widget build(BuildContext context) {
    final attempts = <_Attempt>[];
    final id = (mediaId ?? '').trim();
    final mediaAuth = auth;
    if (id.contains('-') && mediaAuth != null && mediaAuth.canProxy) {
      final preview = mediaAuth.proxyUrl(id, preview: true);
      final full = mediaAuth.proxyUrl(id);
      if (preferFull) {
        if (full != null) attempts.add(_Attempt(full, mediaAuth.headers));
        if (preview != null && preview != full) attempts.add(_Attempt(preview, mediaAuth.headers));
      } else {
        if (preview != null) attempts.add(_Attempt(preview, mediaAuth.headers));
        if (full != null && full != preview) attempts.add(_Attempt(full, mediaAuth.headers));
      }
    }
    final preview = (previewUrl ?? '').trim();
    final full = (url ?? '').trim();
    if (preferFull) {
      if (full.isNotEmpty) attempts.add(_Attempt(full, const {}));
      if (preview.isNotEmpty && preview != full) attempts.add(_Attempt(preview, const {}));
    } else {
      if (preview.isNotEmpty) attempts.add(_Attempt(preview, const {}));
      if (full.isNotEmpty && full != preview) attempts.add(_Attempt(full, const {}));
    }

    if (attempts.isEmpty) return placeholder ?? _defaultPlaceholder();
    return _ChainPhoto(
      attempts: attempts,
      width: width,
      height: height,
      fit: fit,
      placeholder: placeholder ?? _defaultPlaceholder(),
    );
  }

  Widget _defaultPlaceholder() {
    return Container(
      width: width,
      height: height,
      color: Colors.black12,
      child: const Icon(Icons.broken_image_outlined),
    );
  }
}

class _Attempt {
  const _Attempt(this.url, this.headers);
  final String url;
  final Map<String, String> headers;
}

class _ChainPhoto extends StatelessWidget {
  const _ChainPhoto({
    required this.attempts,
    required this.placeholder,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.index = 0,
  });

  final List<_Attempt> attempts;
  final Widget placeholder;
  final double? width;
  final double? height;
  final BoxFit fit;
  final int index;

  @override
  Widget build(BuildContext context) {
    if (index >= attempts.length) return placeholder;
    final attempt = attempts[index];
    return _BytesPhoto(
      url: attempt.url,
      headers: attempt.headers,
      width: width,
      height: height,
      fit: fit,
      onError: _ChainPhoto(
        attempts: attempts,
        placeholder: placeholder,
        width: width,
        height: height,
        fit: fit,
        index: index + 1,
      ),
    );
  }
}

class _BytesPhoto extends StatefulWidget {
  const _BytesPhoto({
    required this.url,
    required this.headers,
    required this.onError,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  final String url;
  final Map<String, String> headers;
  final Widget onError;
  final double? width;
  final double? height;
  final BoxFit fit;

  @override
  State<_BytesPhoto> createState() => _BytesPhotoState();
}

class _BytesPhotoState extends State<_BytesPhoto> {
  Uint8List? _bytes;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await http.get(
        Uri.parse(widget.url),
        headers: widget.headers.isEmpty ? null : widget.headers,
      ).timeout(const Duration(seconds: 25));
      if (res.statusCode >= 200 && res.statusCode < 300 && res.bodyBytes.isNotEmpty) {
        if (mounted) setState(() => _bytes = res.bodyBytes);
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _failed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return widget.onError;
    if (_bytes == null) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return Image.memory(
      _bytes!,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
    );
  }
}
