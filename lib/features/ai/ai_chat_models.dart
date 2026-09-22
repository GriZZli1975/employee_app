class AiChatAttachment {
  AiChatAttachment({
    required this.type,
    required this.url,
    this.previewUrl,
    this.title,
    this.filename,
    this.channel,
    this.duration,
    this.mediaId,
  });

  final String type;
  final String url;
  final String? previewUrl;
  final String? title;
  final String? filename;
  final String? channel;
  final String? duration;
  final String? mediaId;

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
        if (mediaId != null && mediaId!.isNotEmpty) 'media_id': mediaId,
      };

  Map<String, dynamic> toVideoMap() => {
        'url': url,
        'title': displayTitle,
        'thumbnail': previewUrl ?? '',
        'channel': channel ?? '',
        'duration': duration ?? '',
        if (mediaId != null && mediaId!.isNotEmpty) 'media_id': mediaId,
      };

  Map<String, dynamic> toSourceMap() => {
        'url': url,
        'title': displayTitle,
      };

  static AiChatAttachment? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final type = map['type']?.toString() ?? '';
    final url = (map['url'] ?? map['preview_url'] ?? map['href'] ?? '').toString();
    var mediaId = (map['media_id'] ?? map['mediaId'])?.toString();
    if (mediaId == null || mediaId.isEmpty) {
      final sub = map['subtitle']?.toString() ?? '';
      if (RegExp(r'^[0-9a-f-]{8,}$', caseSensitive: false).hasMatch(sub)) mediaId = sub;
    }
    if (type.isEmpty || (url.isEmpty && (mediaId == null || mediaId.isEmpty))) return null;
    return AiChatAttachment(
      type: type,
      url: url,
      previewUrl: map['preview_url']?.toString(),
      title: map['title']?.toString(),
      filename: map['filename']?.toString(),
      channel: map['channel']?.toString(),
      duration: map['duration']?.toString(),
      mediaId: (mediaId != null && mediaId.isNotEmpty) ? mediaId : null,
    );
  }
}

class AiChatMessage {
  AiChatMessage({
    required this.role,
    required this.text,
    this.attachments = const [],
    this.quickReplies = const [],
  })  : images = attachments.where((a) => a.isPhoto).map((a) => a.toImageMap()).toList(),
        videos = attachments.where((a) => a.isVideo).map((a) => a.toVideoMap()).toList(),
        sources = attachments.where((a) => a.isLink).map((a) => a.toSourceMap()).toList(),
        voices = attachments.where((a) => a.isVoice).toList();

  final String role;
  final String text;
  final List<AiChatAttachment> attachments;
  final List<AiQuickReply> quickReplies;
  final List<Map<String, dynamic>> images;
  final List<Map<String, dynamic>> videos;
  final List<Map<String, dynamic>> sources;
  final List<AiChatAttachment> voices;

  bool get isUser => role == 'user';

  static List<AiChatAttachment> parseAttachments(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map(AiChatAttachment.fromJson).whereType<AiChatAttachment>().toList();
  }

  static List<AiChatAttachment> parseReply(dynamic reply) {
    if (reply is! Map) return const [];
    final out = <AiChatAttachment>[];
    final seen = <String>{};
    void addAll(Iterable<AiChatAttachment> items) {
      for (final item in items) {
        final key = (item.mediaId != null && item.mediaId!.isNotEmpty)
            ? '${item.type}:${item.mediaId}'
            : '${item.type}:${item.url}';
        if (seen.add(key)) out.add(item);
      }
    }

    addAll(parseAttachments(reply['attachments']));
    final blocks = reply['blocks'];
    if (blocks is List) {
      for (final block in blocks) {
        if (block is Map) addAll(parseAttachments(block['attachments']));
      }
    }
    return out;
  }

  static String parseText(dynamic reply) {
    if (reply is! Map) return '';
    return stripQuickRepliesBlock((reply['content'] ?? reply['text'] ?? '').toString());
  }

  /// Убирает служебный блок <!--quick_replies:[...]--> (или с ошибочным `}` вместо `-->`).
  static String stripQuickRepliesBlock(String text) {
    final start = RegExp(r'<!--\s*quick_replies\s*:\s*', caseSensitive: false).firstMatch(text);
    if (start == null) return text.trim();
    return text.substring(0, start.start).trim();
  }

  /// Если API не отдал quick_replies, пробуем вытащить их из текста ответа.
  static List<AiQuickReply> parseEmbeddedQuickReplies(String text) {
    final start = RegExp(r'<!--\s*quick_replies\s*:\s*', caseSensitive: false).firstMatch(text);
    if (start == null) return const [];
    final open = text.indexOf('[', start.end);
    if (open == -1) return const [];

    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = open; i < text.length; i++) {
      final ch = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (ch == r'\') {
          escaped = true;
        } else if (ch == '"') {
          inString = false;
        }
        continue;
      }
      if (ch == '"') {
        inString = true;
        continue;
      }
      if (ch == '[') depth++;
      if (ch == ']') {
        depth--;
        if (depth == 0) {
          try {
            return AiQuickReply.parseList(text.substring(open, i + 1));
          } catch (_) {
            return const [];
          }
        }
      }
    }
    return const [];
  }

  static bool looksLikeInspectionQuery(String text) {
    final t = text.toLowerCase().replaceAll('ё', 'е');
    if (RegExp(r'как\s+(сделать|провести|выполнить)').hasMatch(t)) return false;
    return RegExp(r'диагностик|осмотр|отч[её]т|последн|результат|фото\s+диагност|голос|аудио').hasMatch(t);
  }

  static String formatInspectionReport(dynamic raw) {
    if (raw is! Map) return '';
    final map = Map<String, dynamic>.from(raw);
    final buf = StringBuffer();
    final meta = map['meta'] is Map ? Map<String, dynamic>.from(map['meta'] as Map) : <String, dynamic>{};
    final kind = meta['kind']?.toString() == 'diagnostics' ? 'Диагностика' : 'Осмотр';
    final plate = (meta['plate'] ?? '').toString().trim();
    final when = (meta['completed_at'] ?? '').toString();
    buf.writeln(
      [
        kind,
        if (plate.isNotEmpty) plate,
        if (when.length >= 10) when.substring(0, 16).replaceFirst('T', ' '),
      ].join(' · '),
    );
    final summary = (map['summary'] ?? '').toString().trim();
    if (summary.isNotEmpty) {
      buf.writeln();
      buf.writeln(summary);
    }

    final works = <String>[];
    String? transcript;
    final blocks = map['blocks'];
    if (blocks is List) {
      for (final b in blocks) {
        if (b is! Map) continue;
        final type = b['type']?.toString();
        if (type == 'work') {
          final title = (b['title'] ?? '').toString().trim();
          if (title.isEmpty) continue;
          final defect = (b['defect'] ?? '').toString().trim();
          final desc = (b['description'] ?? '').toString().trim();
          final extra = [defect, desc].where((s) => s.isNotEmpty).join(' — ');
          works.add(extra.isEmpty ? title : '$title — $extra');
        } else if (type == 'transcript') {
          final t = (b['text'] ?? '').toString().trim();
          if (t.isNotEmpty) transcript = t;
        }
      }
    }
    if (works.isNotEmpty) {
      buf.writeln();
      buf.writeln('Рекомендуемые работы:');
      for (var i = 0; i < works.length; i++) {
        buf.writeln('${i + 1}. ${works[i]}');
      }
    }
    final tr = (map['transcript'] ?? transcript ?? '').toString().trim();
    if (tr.isNotEmpty) {
      buf.writeln();
      buf.writeln('Расшифровка / комментарий:');
      buf.writeln(tr);
    }
    return buf.toString().trim();
  }
}

class AiChatTemplate {
  AiChatTemplate({
    required this.id,
    required this.label,
    required this.displayMessage,
    this.description,
  });

  final String id;
  final String label;
  final String displayMessage;
  final String? description;

  static AiChatTemplate? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final id = map['id']?.toString() ?? '';
    final label = map['label']?.toString() ?? '';
    final display = (map['display_message'] ?? map['displayMessage'] ?? label).toString();
    if (id.isEmpty || label.isEmpty) return null;
    return AiChatTemplate(
      id: id,
      label: label,
      displayMessage: display,
      description: map['description']?.toString(),
    );
  }
}

class AiQuickReply {
  AiQuickReply({
    required this.id,
    required this.label,
    required this.message,
    this.templateId,
  });

  final String id;
  final String label;
  final String message;
  final String? templateId;

  static List<AiQuickReply> parseList(dynamic raw) {
    if (raw is! List) return const [];
    final out = <AiQuickReply>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final label = map['label']?.toString() ?? '';
      final message = map['message']?.toString() ?? '';
      if (label.isEmpty || message.isEmpty) continue;
      out.add(
        AiQuickReply(
          id: map['id']?.toString() ?? 'qr-${out.length + 1}',
          label: label,
          message: message,
          templateId: (map['template_id'] ?? map['templateId'])?.toString(),
        ),
      );
    }
    return out;
  }
}
