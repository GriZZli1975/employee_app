class AiChatAttachment {
  AiChatAttachment({
    required this.type,
    required this.url,
    this.previewUrl,
    this.title,
    this.filename,
    this.channel,
    this.duration,
  });

  final String type;
  final String url;
  final String? previewUrl;
  final String? title;
  final String? filename;
  final String? channel;
  final String? duration;

  bool get isPhoto => type == 'photo';
  bool get isVideo => type == 'video';
  bool get isVoice => type == 'voice' || type == 'audio';
  bool get isLink => type == 'link';

  String get displayTitle {
    final t = title?.trim();
    if (t != null && t.isNotEmpty) return t;
    final f = filename?.trim();
    if (f != null && f.isNotEmpty) return f;
    if (isPhoto) return 'Фото';
    if (isVideo) return 'Видео';
    if (isVoice) return 'Аудио';
    return 'Ссылка';
  }

  Map<String, dynamic> toImageMap() => {
        'url': url,
        'thumbnail': previewUrl ?? url,
        'title': displayTitle,
      };

  Map<String, dynamic> toVideoMap() => {
        'url': url,
        'title': displayTitle,
        'thumbnail': previewUrl ?? '',
        'channel': channel ?? '',
        'duration': duration ?? '',
      };

  Map<String, dynamic> toSourceMap() => {
        'url': url,
        'title': displayTitle,
      };

  static AiChatAttachment? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final type = map['type']?.toString() ?? '';
    final url = map['url']?.toString() ?? '';
    if (type.isEmpty || url.isEmpty) return null;
    return AiChatAttachment(
      type: type,
      url: url,
      previewUrl: map['preview_url']?.toString(),
      title: map['title']?.toString(),
      filename: map['filename']?.toString(),
      channel: map['channel']?.toString(),
      duration: map['duration']?.toString(),
    );
  }
}

class AiChatMessage {
  AiChatMessage({
    required this.role,
    required this.text,
    this.attachments = const [],
  })  : images = attachments.where((a) => a.isPhoto).map((a) => a.toImageMap()).toList(),
        videos = attachments.where((a) => a.isVideo).map((a) => a.toVideoMap()).toList(),
        sources = attachments.where((a) => a.isLink).map((a) => a.toSourceMap()).toList(),
        voices = attachments.where((a) => a.isVoice).toList();

  final String role;
  final String text;
  final List<AiChatAttachment> attachments;
  final List<Map<String, dynamic>> images;
  final List<Map<String, dynamic>> videos;
  final List<Map<String, dynamic>> sources;
  final List<AiChatAttachment> voices;

  bool get isUser => role == 'user';

  static List<AiChatAttachment> parseAttachments(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map(AiChatAttachment.fromJson).whereType<AiChatAttachment>().toList();
  }
}
