import 'package:intl/intl.dart';

class StooxWorkOrder {
  StooxWorkOrder(this.raw);

  final Map<String, dynamic> raw;

  String get saleNumber =>
      raw['sale_number']?.toString() ??
      raw['works_check_number']?.toString() ??
      raw['id']?.toString() ??
      '—';

  String? get regNumber => raw['reg_number']?.toString();
  String? get mark => raw['mark_name']?.toString();
  String? get model => raw['model_name']?.toString();
  String? get client => raw['client_name']?.toString();
  String? get employee =>
      raw['emp_name']?.toString() ?? raw['user_name_full']?.toString();
  String? get createdAt => raw['created_at']?.toString();
  String? get vin => raw['vin']?.toString();

  int? get clientId => _int(raw['client_id'] ?? raw['clientId']);
  int? get carId => _int(raw['car_id'] ?? raw['carId']);
  int? get saleId => _int(raw['sale_id'] ?? raw['id'] ?? raw['saleId']);

  /// Открытый ЗН: `closed` = 0 / false / нет поля. Закрытый — не в «В работе».
  bool get isOpen {
    final c = raw['closed'];
    if (c == null) return true;
    if (c == false || c == 0 || c == '0') return true;
    if (c is num) return c == 0;
    final s = c.toString().trim().toLowerCase();
    return s.isEmpty || s == 'false' || s == '0';
  }

  /// Причина обращения / заметка ЗН из Stoox (`sh_reason`, `sh_note`).
  String? get shReason => _cleanNote(raw['sh_reason'] ?? raw['reason']);
  String? get shNote => _cleanNote(raw['sh_note'] ?? raw['note']);
  bool get hasClientNotes {
    final r = shReason;
    final n = shNote;
    return (r != null && r.isNotEmpty) || (n != null && n.isNotEmpty);
  }

  /// Актуальная запись на ремонт: с максимальным `date_end`.
  StooxPlanningSlot? get latestPlanning {
    final slots = planningSlots;
    if (slots.isEmpty) return null;
    slots.sort((a, b) {
      final ae = a.end ?? a.start;
      final be = b.end ?? b.start;
      if (ae == null && be == null) return 0;
      if (ae == null) return 1;
      if (be == null) return -1;
      return be.compareTo(ae);
    });
    return slots.first;
  }

  List<StooxPlanningSlot> get planningSlots {
    final rawList = raw['records'];
    final list = <dynamic>[];
    if (rawList is List) {
      list.addAll(rawList);
    } else if (rawList is Map) {
      list.addAll(rawList.values);
    }
    final out = <StooxPlanningSlot>[];
    for (final item in list) {
      if (item is! Map) continue;
      final slot = StooxPlanningSlot.fromMap(Map<String, dynamic>.from(item));
      if (slot.start != null || slot.end != null) out.add(slot);
    }
    return out;
  }

  DateTime? get planningEnd => latestPlanning?.end ?? latestPlanning?.start;

  /// Плановое время вышло — авто «зависло» относительно записи.
  bool get isPlanningOverdue {
    final end = planningEnd;
    if (end == null) return false;
    return end.isBefore(DateTime.now());
  }

  String? get planningRangeLabel => latestPlanning?.rangeLabel;

  /// Только время актуальной записи (дата — в заголовке линейки).
  String? get planningTimeLabel => latestPlanning?.timeLabel;

  /// День для группировки линейки (по date_end актуальной записи).
  DateTime? get planningDay {
    final end = planningEnd ?? latestPlanning?.start;
    if (end == null) return null;
    return DateTime(end.year, end.month, end.day);
  }

  /// Сортировка «В работе»: просроченные сверху, затем ближайший `date_end`.
  static int compareByPlanningPriority(StooxWorkOrder a, StooxWorkOrder b) {
    final now = DateTime.now();
    final aEnd = a.planningEnd;
    final bEnd = b.planningEnd;
    final aOver = aEnd != null && aEnd.isBefore(now);
    final bOver = bEnd != null && bEnd.isBefore(now);
    if (aOver != bOver) return aOver ? -1 : 1;
    if (aEnd == null && bEnd == null) return 0;
    if (aEnd == null) return 1;
    if (bEnd == null) return -1;
    if (aOver && bOver) return aEnd.compareTo(bEnd);
    return aEnd.compareTo(bEnd);
  }

  static List<dynamic> sortOpenBaskets(List<dynamic> items) {
    final mapped = items
        .whereType<Map>()
        .map((e) => MapEntry(e, StooxWorkOrder(Map<String, dynamic>.from(e))))
        .toList();
    mapped.sort((a, b) => compareByPlanningPriority(a.value, b.value));
    return [
      for (final e in mapped) e.key,
      ...items.where((e) => e is! Map),
    ];
  }

  /// Группы для вертикальной линейки: день → авто (уже отсортированные).
  static List<({DateTime? day, List<StooxWorkOrder> orders})> groupByPlanningDay(
    List<dynamic> items,
  ) {
    final sorted = sortOpenBaskets(items)
        .whereType<Map>()
        .map((e) => StooxWorkOrder(Map<String, dynamic>.from(e)))
        .toList();
    final groups = <DateTime?, List<StooxWorkOrder>>{};
    final orderKeys = <DateTime?>[];
    for (final o in sorted) {
      final day = o.planningDay;
      if (!groups.containsKey(day)) {
        groups[day] = [];
        orderKeys.add(day);
      }
      groups[day]!.add(o);
    }
    // Просроченные дни / без даты сверху уже заданы sortOpenBaskets;
    // внутри ключей сохраняем порядок первого появления.
    return [
      for (final day in orderKeys) (day: day, orders: groups[day]!),
    ];
  }

  StooxWorkOrder withWorks(List<StooxLineItem> works) {
    final map = Map<String, dynamic>.from(raw);
    map['works'] = works.map((w) => Map<String, dynamic>.from(w.raw)).toList();
    return StooxWorkOrder(map);
  }

  static String? _cleanNote(dynamic value) {
    if (value == null) return null;
    var s = value.toString().trim();
    if (s.isEmpty || s == '-' || s == 'null') return null;
    // Убрать пустые сегменты вида "; -; -" и лишние кавычки.
    final parts = <String>[];
    for (final rawPart in s.split(';')) {
      var p = rawPart.trim();
      while (p.startsWith("'") || p.startsWith('"')) {
        p = p.substring(1);
      }
      while (p.endsWith("'") || p.endsWith('"')) {
        p = p.substring(0, p.length - 1);
      }
      p = p.trim();
      if (p.isEmpty || p == '-') continue;
      parts.add(p);
    }
    s = parts.join('\n').trim();
    return s.isEmpty ? null : s;
  }

  num? get totalSum {
    final v = raw['sum'] ?? raw['appraisal'];
    if (v is num) return v;
    return num.tryParse(v?.toString() ?? '');
  }

  num? get clientBalance => _num(raw['client_balance']);
  num? get clientBalanceJur => _num(raw['client_balance_jur']);

  static const _scalarMergeKeys = [
    'client_balance',
    'client_balance_jur',
    'client_id',
    'car_id',
    'sale_id',
    'reg_number',
    'mark_name',
    'model_name',
  ];

  static const _worksKeys = ['works', 'work_list', 'work_items', 'services', 'uslugi', 'work'];
  static const _partsKeys = ['parts', 'spare_parts', 'zch', 'details'];
  static const _cleaningKeys = ['cleaning', 'cleaning_works'];
  static const _mergeKeys = [..._worksKeys, ..._partsKeys, ..._cleaningKeys];

  List<StooxLineItem> get works => _firstLines(_worksKeys);
  List<StooxLineItem> get parts => _firstLines(_partsKeys);
  List<StooxLineItem> get cleaning => _firstLines(_cleaningKeys);

  String get carInfo {
    final bits = [
      if (mark != null || model != null) '${mark ?? ''} ${model ?? ''}'.trim(),
      if (regNumber != null && regNumber!.isNotEmpty) '($regNumber)',
    ];
    return bits.join(' ');
  }

  static String? employeeIdFromSummary(Map<String, dynamic> summary) {
    for (final key in ['employee_id', 'id', 'individual_id', 'user_id']) {
      final v = summary[key];
      if (v != null && v.toString().trim().isNotEmpty) {
        return v.toString().trim();
      }
    }
    return null;
  }

  static String? employeeNameFromSummary(Map<String, dynamic> summary) {
    final named = [
      summary['name'],
      summary['full_name'],
      summary['emp_name'],
      summary['user_name_full'],
    ];
    for (final v in named) {
      if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
    }
    final parts = [summary['last_name'], summary['first_name'], summary['middle_name']]
        .where((v) => v != null && v.toString().trim().isNotEmpty)
        .map((e) => e.toString().trim());
    final joined = parts.join(' ');
    return joined.isEmpty ? null : joined;
  }

  StooxWorkOrder enrichFromCatalogs(List<Iterable<dynamic>> catalogs) {
    if (works.isNotEmpty) return this;
    final merged = Map<String, dynamic>.from(raw);
    for (final catalog in catalogs) {
      final match = _findMatchingRecord(raw, catalog);
      if (match == null) continue;
      for (final key in _mergeKeys) {
        if (_isEmptyLines(merged[key]) && !_isEmptyLines(match[key])) {
          merged[key] = match[key];
        }
      }
      for (final key in _scalarMergeKeys) {
        if ((merged[key] == null || merged[key].toString().isEmpty) && match[key] != null) {
          merged[key] = match[key];
        }
      }
      final enriched = StooxWorkOrder(merged);
      if (enriched.works.isNotEmpty) return enriched;
    }
    return StooxWorkOrder(merged);
  }

  static Map<String, dynamic>? _findMatchingRecord(
    Map<String, dynamic> source,
    Iterable<dynamic> catalog,
  ) {
    final sourceSn = _normalizeId(source['sale_number'] ?? source['works_check_number']);
    final sourceId = _normalizeId(source['id'] ?? source['sale_id']);
    final sourcePlate = _normalizeId(source['reg_number']);

    for (final item in catalog) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final sn = _normalizeId(map['sale_number'] ?? map['works_check_number']);
      final id = _normalizeId(map['id'] ?? map['sale_id']);
      final plate = _normalizeId(map['reg_number']);
      if (sourceSn != null && sn != null && sourceSn == sn) return map;
      if (sourceId != null && id != null && sourceId == id) return map;
      if (sourcePlate != null && plate != null && sourcePlate == plate && sourceSn != null && sn != null && sourceSn == sn) {
        return map;
      }
    }
    return null;
  }

  static String? _normalizeId(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static bool _isEmptyLines(dynamic value) {
    if (value == null) return true;
    if (value is List) return value.isEmpty;
    if (value is Map) return value.isEmpty;
    return true;
  }

  List<StooxLineItem> _firstLines(List<String> keys) {
    for (final key in keys) {
      final lines = _lines(raw[key]);
      if (lines.isNotEmpty) return lines;
    }
    return [];
  }

  List<StooxLineItem> _lines(dynamic value) {
    if (value == null) return [];
    if (value is List) {
      return value
          .whereType<Map>()
          .map((e) => StooxLineItem(Map<String, dynamic>.from(e)))
          .toList();
    }
    if (value is Map) {
      if (value.isEmpty) return [];
      final catalog = <StooxLineItem>[];
      var numericKeys = 0;
      for (final entry in value.entries) {
        if (entry.value is! Map) continue;
        final map = Map<String, dynamic>.from(entry.value as Map);
        // Ключ хеша MCP — это basket_work_id; внутренний id часто work_id из каталога.
        if (int.tryParse(entry.key.toString()) != null) {
          map['basket_work_id'] = map['basket_work_id'] ?? entry.key;
        }
        map.putIfAbsent('id', () => entry.key);
        catalog.add(StooxLineItem(map));
        if (int.tryParse(entry.key.toString()) != null) numericKeys += 1;
      }
      if (catalog.isNotEmpty && (numericKeys == catalog.length || catalog.length > 1)) {
        return catalog;
      }
      return [StooxLineItem(Map<String, dynamic>.from(value))];
    }
    return [];
  }

  static int? _int(dynamic value) {
    if (value == null) return null;
    if (value is int) return value > 0 ? value : null;
    final n = int.tryParse(value.toString());
    return n != null && n > 0 ? n : null;
  }

  static num? _num(dynamic value) {
    if (value == null) return null;
    if (value is num) return value;
    return num.tryParse(value.toString().replaceAll(' ', '').replaceAll(',', '.'));
  }
}

class StooxPlanningSlot {
  StooxPlanningSlot({this.start, this.end, this.boxId});

  final DateTime? start;
  final DateTime? end;
  final int? boxId;

  factory StooxPlanningSlot.fromMap(Map<String, dynamic> map) {
    return StooxPlanningSlot(
      start: parseStooxDateTime(map['date_start'] ?? map['record_start']),
      end: parseStooxDateTime(map['date_end'] ?? map['record_end']),
      boxId: StooxWorkOrder._int(map['box_id']),
    );
  }

  bool get isOverdue {
    final e = end ?? start;
    if (e == null) return false;
    return e.isBefore(DateTime.now());
  }

  String get rangeLabel {
    final s = start;
    final e = end;
    if (s == null && e == null) return '';
    if (s != null && e != null) {
      return '${_fmtDateTime(s)} – ${_fmtDateTime(e)}';
    }
    if (s != null) return 'с ${_fmtDateTime(s)}';
    return 'до ${_fmtDateTime(e!)}';
  }

  /// Только часы:минуты для строки авто в линейке.
  String get timeLabel {
    final s = start;
    final e = end;
    if (s == null && e == null) return '';
    if (s != null && e != null) {
      if (_sameDay(s, e)) return '${_fmtTime(s)} – ${_fmtTime(e)}';
      return '${_fmtDateTime(s)} – ${_fmtDateTime(e)}';
    }
    if (s != null) return _fmtTime(s);
    return _fmtTime(e!);
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _fmtTime(DateTime d) {
    final hh = d.hour.toString().padLeft(2, '0');
    final mi = d.minute.toString().padLeft(2, '0');
    return '$hh:$mi';
  }

  static String _fmtDateTime(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd.$mm ${_fmtTime(d)}';
  }
}

/// Парсер дат Stoox: `22.09.2026 11:30:00` или ISO.
DateTime? parseStooxDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  final s = value.toString().trim();
  if (s.isEmpty) return null;
  final ru = RegExp(
    r'^(\d{1,2})\.(\d{1,2})\.(\d{4})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?$',
  );
  final m = ru.firstMatch(s);
  if (m != null) {
    return DateTime(
      int.parse(m.group(3)!),
      int.parse(m.group(2)!),
      int.parse(m.group(1)!),
      int.parse(m.group(4) ?? '0'),
      int.parse(m.group(5) ?? '0'),
      int.parse(m.group(6) ?? '0'),
    );
  }
  return DateTime.tryParse(s.replaceFirst(' ', 'T'));
}

class StooxLineItem {
  StooxLineItem(this.raw);

  final Map<String, dynamic> raw;

  String get name =>
      raw['name']?.toString() ??
      raw['title']?.toString() ??
      raw['work_name']?.toString() ??
      raw['service_name']?.toString() ??
      raw['part_name']?.toString() ??
      '—';

  num get qty {
    final v = raw['qty'] ?? raw['quantity'] ?? 1;
    if (v is num) return v;
    return num.tryParse(v.toString()) ?? 1;
  }

  num? get unitPrice {
    for (final key in ['price_discount', 'price', 'sum', 'amount', 'cost']) {
      final v = raw[key];
      if (v is num) return v;
      final p = num.tryParse(v?.toString() ?? '');
      if (p != null) return p;
    }
    return null;
  }

  num? get lineTotal {
    final v = raw['sum'] ?? raw['total'];
    if (v is num) return v;
    final p = num.tryParse(v?.toString() ?? '');
    if (p != null) return p;
    final unit = unitPrice;
    if (unit != null) return unit * qty;
    return null;
  }

  /// `baskets > works > id` из MCP employee-tool — это id строки в корзине.
  int? get basketWorkId {
    final v = raw['basket_work_id'] ?? raw['basketWorkId'] ?? raw['id'];
    if (v is int) return v > 0 ? v : null;
    final n = int.tryParse(v?.toString() ?? '');
    return n != null && n > 0 ? n : null;
  }

  bool get toWorkshop {
    final v = raw['to_workshop'] ?? raw['toWorkshop'] ?? raw['is_done'] ?? raw['done'];
    if (v == true || v == 1 || v == '1') return true;
    if (v is num) return v != 0;
    return v?.toString() == 'true';
  }

  StooxLineItem withToWorkshop(bool value) {
    final map = Map<String, dynamic>.from(raw);
    map['to_workshop'] = value ? 1 : 0;
    return StooxLineItem(map);
  }
}

class StooxFormat {
  static final _money = NumberFormat('#,##0.##', 'ru_RU');

  static String money(num value) => '${_money.format(value)} ₽';

  static String qty(num value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }
}

class StooxMcpDashboard {
  StooxMcpDashboard(this.raw);

  final Map<String, dynamic> raw;

  Map<String, dynamic> get summary =>
      Map<String, dynamic>.from(raw['summary'] as Map? ?? {});

  Map<String, dynamic>? get balance {
    final v = raw['balance'];
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  List<dynamic> get baskets => StooxApiLists.extract(raw['baskets']);
  List<dynamic> get sales => StooxApiLists.extract(raw['sales']);
  List<dynamic> get warranty => StooxApiLists.extract(raw['warranty']);
}

class StooxBalanceInfo {
  StooxBalanceInfo(this.raw);

  final Map<String, dynamic> raw;

  String? get fullName {
    final parts = [
      raw['last_name'],
      raw['first_name'],
      raw['middle_name'],
    ].where((v) => v != null && v.toString().isNotEmpty).map((e) => e.toString());
    final name = parts.join(' ').trim();
    return name.isEmpty ? null : name;
  }

  String? get position => raw['position_name']?.toString();

  num? _num(String key) {
    final v = raw[key];
    if (v is num) return v;
    return num.tryParse(v?.toString() ?? '');
  }

  bool _show(String key) {
    final v = raw[key];
    if (v is bool) return v;
    if (v is num) return v != 0;
    return v?.toString() == '1' || v == true;
  }

  num? get balance => _num('balance');
  num? get lastMonthSalary =>
      _show('show_last_month_salary') ? _num('last_month_salary') : null;
  num? get thisMonthSalary =>
      _show('show_this_month_salary') ? _num('this_month_salary') : null;
  num? get lastMonthNh => _show('show_last_month_nh') ? _num('last_month_nh') : null;
  num? get thisMonthNh => _show('show_this_month_nh') ? _num('this_month_nh') : null;

  List<StooxBalanceRow> get rows {
    final out = <StooxBalanceRow>[];
    if (balance != null) {
      out.add(StooxBalanceRow('Текущий баланс', balance!));
    }
    if (lastMonthSalary != null) {
      out.add(StooxBalanceRow('Начислено за прошлый месяц', lastMonthSalary!));
    }
    if (thisMonthSalary != null && thisMonthSalary != 0) {
      out.add(StooxBalanceRow('Начислено за текущий месяц', thisMonthSalary!));
    }
    if (lastMonthNh != null && lastMonthNh != 0) {
      out.add(StooxBalanceRow('Н/Ч за прошлый месяц', lastMonthNh!));
    }
    if (thisMonthNh != null && thisMonthNh != 0) {
      out.add(StooxBalanceRow('Н/Ч за текущий месяц', thisMonthNh!));
    }
    return out;
  }
}

class StooxBalanceRow {
  const StooxBalanceRow(this.label, this.amount);
  final String label;
  final num amount;
}

class StooxApiLists {
  static List<dynamic> extract(dynamic value) {
    if (value == null) return [];
    if (value is List) return value;
    if (value is Map) {
      if (value.isEmpty) return [];
      final catalog = _entityCatalog(value);
      if (catalog != null) return catalog;
      for (final key in const [
        'items',
        'data',
        'baskets',
        'sales',
        'warranty',
        'orders',
        'work_orders',
      ]) {
        final nested = value[key];
        if (nested is List) return nested;
      }
      if (_looksLikeEntity(value)) return [value];
      final values = value.values.toList();
      if (values.isNotEmpty && values.every((v) => v is Map) && values.every((v) => v is! List)) {
        return values;
      }
      for (final nested in value.values) {
        if (nested is List) return nested;
      }
      return [value];
    }
    return [];
  }

  static List<dynamic>? _entityCatalog(Map value) {
    final catalog = <dynamic>[];
    for (final entry in value.entries) {
      final v = entry.value;
      if (v is! Map) continue;
      if (int.tryParse(entry.key.toString()) != null && _looksLikeEntity(v)) {
        catalog.add(v);
      }
    }
    return catalog.isEmpty ? null : catalog;
  }

  static bool _looksLikeEntity(Map value) {
    final reg = value['reg_number']?.toString().trim();
    if (reg != null && reg.isNotEmpty) return true;
    if (value.containsKey('mark_name') ||
        value.containsKey('sale_number') ||
        value.containsKey('works_check_number')) {
      return true;
    }
    if (value.containsKey('car_id') &&
        (value.containsKey('model_name') || value.containsKey('mark_name'))) {
      return true;
    }
    return false;
  }
}
