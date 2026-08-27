import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'session.dart';
import 'work_order.dart';

class BotApiException implements Exception {
  BotApiException(this.status, this.message);

  final int status;
  final String message;

  @override
  String toString() => status > 0 ? 'HTTP $status — $message' : message;
}

class BotApi {
  BotApi(this.session);

  final EmployeeSession session;
  static const _timeout = Duration(seconds: 90);

  Future<Map<String, String>> _headers() async {
    final host = await session.getBaseUrl();
    final pcKey = await session.getPcKey() ?? '';
    final apiKey = await session.getApiKey();
    return {
      'Content-Type': 'application/json',
      'X-Stoox-Host': host,
      'X-Pc-Key': pcKey,
      'X-Stoox-Key': apiKey,
    };
  }

  Future<String> _base() async {
    final url = EmployeeSession.normalizeBotUrl(await session.getBotUrl());
    if (url.isEmpty) {
      throw BotApiException(0, 'Не задан URL сервиса бота');
    }
    return url;
  }

  Future<Map<String, dynamic>> pingMe() async {
    final res = await http
        .get(Uri.parse('${await _base()}/api/employee/me'), headers: await _headers())
        .timeout(const Duration(seconds: 20));
    return _decode(res);
  }

  Future<Map<String, dynamic>> uploadFile({
    required File file,
    required String kind,
    required String messageType,
    required String filename,
    required String mimeType,
    StooxWorkOrder? order,
    String? sessionId,
    int? employeeId,
  }) async {
    final bytes = await file.readAsBytes();
    final body = <String, dynamic>{
      'file_base64': base64Encode(bytes),
      'filename': filename,
      'mime_type': mimeType,
      'message_type': messageType,
      'kind': kind,
      'session_id': ?sessionId,
      'employee_id': ?employeeId,
      if (order?.regNumber != null) 'plate': order!.regNumber,
      if (order?.vin != null) 'vin': order!.vin,
      if (order?.clientId != null) 'client_id': order!.clientId,
      if (order?.carId != null) 'car_id': order!.carId,
      if (order?.saleId != null) 'sale_id': order!.saleId,
    };
    final res = await http
        .post(
          Uri.parse('${await _base()}/api/media'),
          headers: await _headers(),
          body: jsonEncode(body),
        )
        .timeout(_timeout);
    return _decode(res);
  }

  Future<Map<String, dynamic>> chat({
    required String message,
    required int employeeId,
    String? employeeName,
    String? conversationId,
    Map<String, dynamic>? context,
  }) async {
    final body = <String, dynamic>{
      'employee_id': employeeId,
      'message': message,
      if (employeeName != null && employeeName.isNotEmpty) 'employee_name': employeeName,
      if (conversationId != null && conversationId.isNotEmpty) 'conversation_id': conversationId,
      'context': ?context,
    };
    final res = await http
        .post(
          Uri.parse('${await _base()}/api/ai/chat'),
          headers: await _headers(),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 120));
    return _decode(res);
  }

  Map<String, dynamic> _decode(http.Response res) {
    Map<String, dynamic> data = {};
    if (res.body.isNotEmpty) {
      try {
        final parsed = jsonDecode(res.body);
        if (parsed is Map) data = Map<String, dynamic>.from(parsed);
      } catch (_) {}
    }
    if (res.statusCode >= 400) {
      throw BotApiException(
        res.statusCode,
        data['error']?.toString() ?? data['message']?.toString() ?? res.body,
      );
    }
    return data;
  }
}
