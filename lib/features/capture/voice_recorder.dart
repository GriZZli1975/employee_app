import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class VoiceRecorder {
  AudioRecorder? _recorder;
  String? _path;
  bool _recording = false;

  bool get isRecording => _recording;

  Future<AudioRecorder> _rec() async {
    _recorder ??= AudioRecorder();
    return _recorder!;
  }

  Future<bool> start() async {
    final r = await _rec();
    if (!await r.hasPermission()) return false;
    final dir = await getTemporaryDirectory();
    _path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.wav';
    await r.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 48000,
        numChannels: 1,
      ),
      path: _path!,
    );
    _recording = true;
    return true;
  }

  Future<String?> stop() async {
    if (!_recording) return null;
    final r = await _rec();
    final path = await r.stop();
    _recording = false;
    return path ?? _path;
  }

  Future<void> dispose() async {
    if (_recording) {
      try {
        await (await _rec()).stop();
      } catch (_) {}
      _recording = false;
    }
    await _recorder?.dispose();
    _recorder = null;
  }
}
