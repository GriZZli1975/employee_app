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
      final records = value.values.whereType<Map>().toList();
      if (records.isNotEmpty) {
        return records.map((e) => StooxLineItem(Map<String, dynamic>.from(e))).toList();
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

  List<dynamic> get baskets => StooxApiLists.extract(raw['baskets']);
  List<dynamic> get sales => StooxApiLists.extract(raw['sales']);
  List<dynamic> get warranty => StooxApiLists.extract(raw['warranty']);
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
