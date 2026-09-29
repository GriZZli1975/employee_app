import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Кнопка микрофона: удержание или до [maxDuration], кольцо зелёный→красный.
class VoiceRecordButton extends StatefulWidget {
  const VoiceRecordButton({
    super.key,
    required this.recording,
    required this.onStart,
    required this.onStop,
    this.maxDuration = const Duration(seconds: 30),
    this.size = 72,
  });

  final bool recording;
  final Future<bool> Function() onStart;
  final Future<void> Function() onStop;
  final Duration maxDuration;
  final double size;

  @override
  State<VoiceRecordButton> createState() => _VoiceRecordButtonState();
}

class _VoiceRecordButtonState extends State<VoiceRecordButton> {
  Timer? _tick;
  DateTime? _started;
  double _progress = 0;

  @override
  void didUpdateWidget(covariant VoiceRecordButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.recording && oldWidget.recording) {
      _stopTick(resetProgress: true);
    }
    if (widget.recording && !oldWidget.recording && _started == null) {
      _started = DateTime.now();
      _startTick();
    }
  }

  @override
  void dispose() {
    _stopTick(resetProgress: true);
    super.dispose();
  }

  void _startTick() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 50), (_) {
      final start = _started;
      if (start == null || !widget.recording) return;
      final elapsed = DateTime.now().difference(start);
      final p = (elapsed.inMilliseconds / widget.maxDuration.inMilliseconds).clamp(0.0, 1.0);
      if (p >= 1.0) {
        unawaited(_finishRecording(auto: true));
        return;
      }
      if (mounted) setState(() => _progress = p);
    });
  }

  void _stopTick({required bool resetProgress}) {
    _tick?.cancel();
    _tick = null;
    if (resetProgress && mounted) setState(() => _progress = 0);
    _started = null;
  }

  Future<void> _beginRecording() async {
    if (widget.recording) return;
    final ok = await widget.onStart();
    if (!ok || !mounted) return;
    await HapticFeedback.mediumImpact();
    setState(() {
      _started = DateTime.now();
      _progress = 0;
    });
    _startTick();
  }

  Future<void> _finishRecording({bool auto = false}) async {
    if (!widget.recording) return;
    _stopTick(resetProgress: true);
    await HapticFeedback.lightImpact();
    await widget.onStop();
    if (auto && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Запись до 30 с сохранена — можно записать ещё')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ringSize = widget.size + 14;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _beginRecording(),
      onTapUp: (_) => _finishRecording(),
      onTapCancel: () => _finishRecording(),
      child: SizedBox(
        width: ringSize,
        height: ringSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (widget.recording)
              CustomPaint(
                size: Size(ringSize, ringSize),
                painter: _VoiceRingPainter(progress: _progress),
              ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.recording ? scheme.error : scheme.primary,
                boxShadow: [
                  BoxShadow(
                    color: (widget.recording ? scheme.error : scheme.primary).withValues(alpha: 0.35),
                    blurRadius: widget.recording ? 16 : 8,
                  ),
                ],
              ),
              child: Icon(
                widget.recording ? Icons.stop : Icons.mic,
                color: scheme.onPrimary,
                size: widget.size * 0.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceRingPainter extends CustomPainter {
  _VoiceRingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 3;
    const start = -math.pi / 2;
    final sweep = 2 * math.pi * progress;

    final rect = Rect.fromCircle(center: center, radius: radius);
    final gradient = SweepGradient(
      startAngle: 0,
      endAngle: 2 * math.pi,
      colors: const [Color(0xFF43A047), Color(0xFFFDD835), Color(0xFFE53935)],
    );
    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, start, sweep, false, paint);
  }

  @override
  bool shouldRepaint(covariant _VoiceRingPainter oldDelegate) => oldDelegate.progress != progress;
}
