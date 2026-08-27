import 'dart:convert';

import 'package:http/http.dart' as http;

import 'session.dart';
import 'work_order.dart';

class StooxApiException implements Exception {
  StooxApiException(this.status, this.message);

  final int status;
  final String message;

  @override
  String toString() => status > 0 ? 'HTTP $status — $message' : message;
}

class StooxApi {
  StooxApi(this.session);

  final EmployeeSession session;
  static const _timeout = Duration(seconds: 60);
  static const _mcpPath = '/mcp/employees';

  Future<StooxMcpDashboard> fetchEmployeeDashboard({
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final now = DateTime.now();
    final from = dateFrom ?? DateTime(now.year, now.month, 1);
    final to = dateTo ?? now;
    final pcKey = await session.getPcKey();
    if (pcKey == null || pcKey.isEmpty) {
      throw StooxApiException(401, 'Отсканируйте QR-ключ сотрудника');
    }
    final inner = await _mcpCall(
      toolName: 'employee-tool',
      arguments: {
        'pc-key': pcKey,
        'date_from': _isoDate(from),
        'date_to': _isoDate(to),
      },
    );
    return StooxMcpDashboard(inner);
  }

  Future<List<dynamic>> fetchWorkOrdersCatalog({
    required String employeeId,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final now = DateTime.now();
    final from = dateFrom ?? DateTime(now.year, now.month, 1);
    final to = dateTo ?? now;
    final inner = await _mcpCall(
      toolName: 'work-orders-tool',
      arguments: {
        'employee_id': employeeId,
        'date_from': _isoDate(from),
        'date_to': _isoDate(to),
      },
    );
    return _extractWorkOrders(inner);
  }

  Future<List<dynamic>> fetchEnrichedBaskets() async {
    final dash = await fetchEmployeeDashboard();
    return enrichBasketItems(
      dash.baskets,
      sales: dash.sales,
      warranty: dash.warranty,
      employeeSummary: dash.summary,
    );
  }

  Future<List<dynamic>> enrichBasketItems(
    List<dynamic> baskets, {
    List<dynamic>? sales,
    List<dynamic>? warranty,
    Map<String, dynamic>? employeeSummary,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    var items = List<dynamic>.from(baskets);
    List<dynamic> workOrders = [];
    final employeeId = employeeSummary == null
        ? null
        : StooxWorkOrder.employeeIdFromSummary(employeeSummary);
    if (employeeId != null) {
      try {
        workOrders = await fetchWorkOrdersCatalog(
          employeeId: employeeId,
          dateFrom: dateFrom,
          dateTo: dateTo,
        );
        if (workOrders.isNotEmpty) {
          items = mergeBasketLists(items, workOrders);
        }
      } on StooxApiException {
        // work-orders-tool может отсутствовать
      }
    }

    final catalogs = <Iterable<dynamic>>[
      ?sales,
      ?warranty,
      if (workOrders.isNotEmpty) workOrders,
      items,
    ];

    return items.map((item) {
      if (item is! Map) return item;
      return StooxWorkOrder(Map<String, dynamic>.from(item)).enrichFromCatalogs(catalogs).raw;
    }).toList();
  }

  static List<dynamic> mergeBasketLists(List<dynamic> primary, List<dynamic> secondary) {
    final out = <dynamic>[];
    final seen = <String>{};
    for (final item in [...primary, ...secondary]) {
      if (item is! Map) {
        out.add(item);
        continue;
      }
      final map = Map<String, dynamic>.from(item);
      final key = _basketMergeKey(map);
      if (seen.add(key)) out.add(map);
    }
    return out;
  }

  static String _basketMergeKey(Map<String, dynamic> map) {
    final id = map['id'] ?? map['sale_id'];
    if (id != null && id.toString().trim().isNotEmpty) {
      return 'id:${id.toString().trim()}';
    }
    final reg = map['reg_number']?.toString().trim();
    if (reg != null && reg.isNotEmpty) return 'reg:$reg';
    return 'hash:${map.hashCode}';
  }

  static List<dynamic> _extractWorkOrders(Map<String, dynamic> payload) {
    for (final key in [
      'work_orders',
      'orders',
      'sales',
      'baskets',
      'warranty',
      'items',
      'data',
    ]) {
      final list = StooxApiLists.extract(payload[key]);
      if (list.isNotEmpty) return list;
    }
    return StooxApiLists.extract(payload);
  }

  Future<String?> fetchBotBaseUrl() async {
    final origin = await session.getBaseUrl();
    final apiKey = await session.getApiKey();
    if (origin.isEmpty || apiKey.isEmpty) return null;

    final paths = ['/outer/api/v1/bot/get-options', '/api/v1/bot/get-options'];
    for (final path in paths) {
      try {
        final res = await http
            .get(
              Uri.parse('$origin$path'),
              headers: {'Key': apiKey, 'Accept': 'application/json'},
            )
            .timeout(_timeout);
        if (res.statusCode >= 400) continue;
        final data = jsonDecode(res.body);
        final options = data is Map ? data['options'] : null;
        final url = botUrlFromOptions(options);
        if (url != null) return url;
      } catch (_) {}
    }
    return null;
  }

  static String? botUrlFromOptions(dynamic options) {
    final map = <String, String>{};
    if (options is List) {
      for (final item in options) {
        if (item is! Map) continue;
        final key = item['key']?.toString() ?? '';
        final value = item['value']?.toString() ?? '';
        if (key.isNotEmpty) map[key] = value;
      }
    } else if (options is Map) {
      for (final entry in options.entries) {
        map[entry.key.toString()] = entry.value?.toString() ?? '';
      }
    }

    const preferred = [
      'OPTION_TELEGRAM_BOT_WEBHOOK_PUBLIC_BASE_URL',
      'OPTION_TELEGRAM_WEBHOOK_PUBLIC_BASE_URL',
      'OPTION_TELEGRAM_BOT_API_URL',
      'OPTION_TELEGRAM_BOT_URL',
    ];
    for (final key in preferred) {
      final url = _asServiceUrl(map[key]);
      if (url != null) return url;
    }
    for (final value in map.values) {
      final url = _asServiceUrl(value);
      if (url != null) return url;
    }
    return null;
  }

  static String? _asServiceUrl(String? raw) {
    if (raw == null) return null;
    final t = raw.trim();
    if (!t.startsWith('http://') && !t.startsWith('https://')) return null;
    final lower = t.toLowerCase();
    if (lower.contains('t.me/') ||
        lower.contains('telegram.me') ||
        lower.contains('telegram.dog')) {
      return null;
    }
    return t.replaceAll(RegExp(r'/+$'), '');
  }

  Future<Map<String, dynamic>> _mcpCall({
    required String toolName,
    required Map<String, dynamic> arguments,
  }) async {
    final baseUrl = await session.getBaseUrl();
    if (baseUrl.isEmpty) {
      throw StooxApiException(0, 'Укажите адрес сервера Stoox');
    }
    final headers = {
      'Content-Type': 'application/json',
      'pc-key': arguments['pc-key']?.toString() ?? await session.getPcKey() ?? '',
      'key': await session.getApiKey(),
    };
    final uri = Uri.parse('$baseUrl$_mcpPath');
    final body = jsonEncode({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'tools/call',
      'params': {
        'name': toolName,
        'arguments': arguments,
      },
    });
    final res = await http.post(uri, headers: headers, body: body).timeout(_timeout);
    return _decodeMcp(res);
  }

  Map<String, dynamic> _decodeMcp(http.Response res) {
    if (res.statusCode >= 400) {
      throw StooxApiException(res.statusCode, _extractError(res.body));
    }
    if (res.body.isEmpty) {
      throw StooxApiException(0, 'Пустой ответ Stoox MCP');
    }
    final data = jsonDecode(res.body);
    if (data is! Map) {
      throw StooxApiException(res.statusCode, 'Неверный ответ Stoox MCP');
    }
    final envelope = Map<String, dynamic>.from(data);
    final err = envelope['error'];
    if (err is Map) {
      throw StooxApiException(
        res.statusCode,
        err['message']?.toString() ?? 'Ошибка Stoox MCP',
      );
    }
    final result = envelope['result'];
    if (result is! Map) {
      throw StooxApiException(res.statusCode, 'Нет result в ответе MCP');
    }
    final content = result['content'];
    if (content is! List || content.isEmpty) {
      throw StooxApiException(res.statusCode, 'Пустой content в ответе MCP');
    }
    final first = content.first;
    if (first is! Map) {
      throw StooxApiException(res.statusCode, 'Неверный формат content MCP');
    }
    final text = first['text']?.toString();
    if (text == null || text.isEmpty) return {};
    final inner = jsonDecode(text);
    if (inner is Map<String, dynamic>) return inner;
    if (inner is Map) return Map<String, dynamic>.from(inner);
    return {'data': inner};
  }

  String _extractError(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map) {
        if (j['error'] is Map) {
          final msg = (j['error'] as Map)['message'];
          if (msg != null) return msg.toString();
        }
        for (final field in ['detail', 'message', 'error', 'msg']) {
          if (j[field] != null) return j[field].toString();
        }
      }
    } catch (_) {}
    return body.isNotEmpty ? body : 'Ошибка Stoox';
  }

  static String _isoDate(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }
}
