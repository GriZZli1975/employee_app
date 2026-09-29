import 'package:camera/camera.dart';

/// Вкл/выкл фонарика без открытия экрана камеры.
class CaptureTorch {
  CameraController? _controller;
  bool isOn = false;

  Future<bool> toggle() async {
    try {
      if (_controller == null) {
        final cameras = await availableCameras();
        if (cameras.isEmpty) return false;
        final back = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => cameras.first,
        );
        final c = CameraController(back, ResolutionPreset.low, enableAudio: false);
        await c.initialize();
        _controller = c;
      }
      final next = !isOn;
      await _controller!.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      isOn = next;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> off() async {
    if (_controller != null && isOn) {
      try {
        await _controller!.setFlashMode(FlashMode.off);
      } catch (_) {}
      isOn = false;
    }
  }

  Future<void> dispose() async {
    await off();
    await _controller?.dispose();
    _controller = null;
  }
}
