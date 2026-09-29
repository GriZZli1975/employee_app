import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

enum _LensMode { photo, video }

/// Камера: фото (серия) или видео, галерея сбоку, фонарик.
class BurstCameraScreen extends StatefulWidget {
  const BurstCameraScreen({
    super.key,
    required this.onPhotoCaptured,
    this.onVideoCaptured,
    this.onGalleryPicked,
    this.maxVideoDuration = const Duration(minutes: 2),
  });

  final Future<void> Function(File file) onPhotoCaptured;
  final Future<void> Function(File file)? onVideoCaptured;
  final Future<void> Function(File file)? onGalleryPicked;
  final Duration maxVideoDuration;

  @override
  State<BurstCameraScreen> createState() => _BurstCameraScreenState();
}

class _BurstCameraScreenState extends State<BurstCameraScreen> {
  CameraController? _controller;
  CameraDescription? _camera;
  String? _error;
  bool _busy = false;
  int _shots = 0;
  bool _torchOn = false;
  _LensMode _mode = _LensMode.photo;
  bool _recordingVideo = false;
  Timer? _videoLimitTimer;

  @override
  void initState() {
    super.initState();
    _initCamera(forVideo: false);
  }

  Future<void> _initCamera({required bool forVideo}) async {
    await _controller?.dispose();
    _controller = null;
    if (!mounted) return;
    setState(() => _error = null);
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'Камера не найдена');
        return;
      }
      _camera ??= cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        _camera!,
        ResolutionPreset.high,
        enableAudio: forVideo,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      if (_torchOn) {
        try {
          await controller.setFlashMode(FlashMode.torch);
        } catch (_) {
          _torchOn = false;
        }
      }
      setState(() => _controller = controller);
    } catch (e) {
      if (mounted) setState(() => _error = 'Не удалось открыть камеру: $e');
    }
  }

  @override
  void dispose() {
    _videoLimitTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _setMode(_LensMode mode) async {
    if (_mode == mode || _recordingVideo) return;
    if (mode == _LensMode.video && widget.onVideoCaptured == null) return;
    setState(() => _mode = mode);
    await _initCamera(forVideo: mode == _LensMode.video);
  }

  Future<void> _toggleTorch() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _recordingVideo) return;
    final next = !_torchOn;
    try {
      await c.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _torchOn = next);
      await HapticFeedback.selectionClick();
    } on CameraException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Подсветка недоступна: ${e.description ?? e.code}')),
      );
    }
  }

  Future<void> _pickGallery() async {
    if (_recordingVideo) return;
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    if (file == null || widget.onGalleryPicked == null) return;
    await widget.onGalleryPicked!(File(file.path));
    if (mounted) setState(() => _shots += 1);
  }

  Future<void> _shootPhoto() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || c.value.isTakingPicture || _busy || _recordingVideo) return;
    setState(() => _busy = true);
    try {
      await HapticFeedback.mediumImpact();
      final shot = await c.takePicture();
      if (!mounted) return;
      setState(() {
        _shots += 1;
        _busy = false;
      });
      unawaited(widget.onPhotoCaptured(File(shot.path)));
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Снимок не удался: $e')));
      }
    }
  }

  Future<void> _toggleVideoRecording() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _busy) return;
    if (!_recordingVideo) {
      try {
        await HapticFeedback.mediumImpact();
        await c.startVideoRecording();
        _videoLimitTimer?.cancel();
        _videoLimitTimer = Timer(widget.maxVideoDuration, () {
          if (_recordingVideo) unawaited(_stopVideoRecording(limitReached: true));
        });
        if (mounted) setState(() => _recordingVideo = true);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось начать видео: $e')));
        }
      }
      return;
    }
    await _stopVideoRecording(limitReached: false);
  }

  Future<void> _stopVideoRecording({required bool limitReached}) async {
    final c = _controller;
    if (c == null || !_recordingVideo) return;
    _videoLimitTimer?.cancel();
    setState(() => _busy = true);
    try {
      final file = await c.stopVideoRecording();
      await HapticFeedback.lightImpact();
      if (mounted) {
        setState(() {
          _recordingVideo = false;
          _busy = false;
          _shots += 1;
        });
      }
      if (widget.onVideoCaptured != null) {
        await widget.onVideoCaptured!(File(file.path));
      }
      if (limitReached && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Достигнут лимит длины видео')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _recordingVideo = false;
          _busy = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Видео не сохранилось: $e')));
      }
    }
  }

  Future<void> _onShutter() async {
    if (_mode == _LensMode.photo) {
      await _shootPhoto();
    } else {
      await _toggleVideoRecording();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final galleryEnabled = widget.onGalleryPicked != null;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (c != null && c.value.isInitialized)
            ClipRect(
              child: OverflowBox(
                alignment: Alignment.center,
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: c.value.previewSize?.height ?? 1,
                    height: c.value.previewSize?.width ?? 1,
                    child: CameraPreview(c),
                  ),
                ),
              ),
            )
          else if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
              ),
            )
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          if (_recordingVideo)
            const Positioned(
              top: 72,
              left: 0,
              right: 0,
              child: Center(
                child: _RecBadge(),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: _recordingVideo ? null : () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white, size: 28),
                      ),
                      const Spacer(),
                      if (_shots > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text('$_shots', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      TextButton(
                        onPressed: _recordingVideo ? null : () => Navigator.pop(context),
                        child: const Text('Готово', style: TextStyle(color: Colors.white, fontSize: 16)),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      SizedBox(
                        width: 72,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _ModeChip(
                              label: 'Фото',
                              selected: _mode == _LensMode.photo,
                              onTap: _recordingVideo ? null : () => _setMode(_LensMode.photo),
                            ),
                            const SizedBox(height: 8),
                            _ModeChip(
                              label: 'Видео',
                              selected: _mode == _LensMode.video,
                              onTap: _recordingVideo ? null : () => _setMode(_LensMode.video),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: _busy && !_recordingVideo ? null : _onShutter,
                              child: Container(
                                width: 78,
                                height: 78,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 5),
                                  color: _recordingVideo
                                      ? Colors.red
                                      : (_busy ? Colors.white24 : Colors.white),
                                ),
                                child: _mode == _LensMode.video && !_recordingVideo
                                    ? const Icon(Icons.videocam, color: Colors.black87)
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _mode == _LensMode.photo
                                  ? 'Снимок'
                                  : (_recordingVideo ? 'Стоп' : 'Запись'),
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 72,
                        child: galleryEnabled
                            ? IconButton(
                                tooltip: 'Галерея',
                                onPressed: _recordingVideo ? null : _pickGallery,
                                icon: const Icon(Icons.photo_library_outlined, color: Colors.white, size: 32),
                              )
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  IconButton(
                    tooltip: _torchOn ? 'Выключить фонарик' : 'Фонарик',
                    onPressed: c == null || !c.value.isInitialized || _recordingVideo ? null : _toggleTorch,
                    icon: Icon(
                      _torchOn ? Icons.flashlight_on : Icons.flashlight_off_outlined,
                      color: _torchOn ? Colors.amber : Colors.white70,
                      size: 28,
                    ),
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

class _RecBadge extends StatelessWidget {
  const _RecBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(20)),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.fiber_manual_record, color: Colors.white, size: 14),
          SizedBox(width: 6),
          Text('REC', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.white : Colors.black45,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.black : Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
