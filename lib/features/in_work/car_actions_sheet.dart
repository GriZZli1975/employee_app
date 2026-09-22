import 'package:flutter/material.dart';

import '../../core/session.dart';
import '../../core/stoox_api.dart';
import '../../core/work_order.dart';
import '../ai/ai_chat_screen.dart';
import '../capture/capture_screen.dart';
import '../works/work_order_screen.dart';

Future<void> showCarActions({
  required BuildContext context,
  required EmployeeSession session,
  required StooxWorkOrder order,
  required StooxApi stocks,
  Map<String, dynamic>? employeeSummary,
  List<dynamic> sales = const [],
  List<dynamic> warranty = const [],
  ValueChanged<StooxWorkOrder>? onOrderUpdated,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final bottom = MediaQuery.paddingOf(ctx).bottom;
      return Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 16 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              order.regNumber ?? order.saleNumber,
              style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (order.carInfo.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(order.carInfo, style: const TextStyle(color: Colors.black54)),
              ),
            if (order.saleNumber.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'ЗН ${order.saleNumber}',
                  style: const TextStyle(color: Colors.black45, fontSize: 13),
                ),
              ),
            const SizedBox(height: 16),
            if (order.hasClientNotes) ...[
              FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _showClientNotes(context, order);
                },
                icon: const Icon(Icons.sticky_note_2_outlined),
                label: const Text('Причина / заметка'),
              ),
              const SizedBox(height: 10),
            ],
            FilledButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                var resolved = order;
                if (resolved.works.isEmpty) {
                  final messenger = ScaffoldMessenger.of(context);
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Загружаем работы из ЗН…')),
                  );
                  try {
                    resolved = await _resolveWorkOrder(
                      order: resolved,
                      client: stocks,
                      employeeSummary: employeeSummary,
                      sales: sales,
                      warranty: warranty,
                    );
                  } catch (_) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Не удалось загрузить работы из Stoox')),
                    );
                  }
                }
                if (!context.mounted) return;
                final updated = await Navigator.of(context).push<StooxWorkOrder>(
                  MaterialPageRoute<StooxWorkOrder>(
                    builder: (_) => WorkOrderScreen(
                      order: resolved,
                      session: session,
                      employeeId: employeeSummary == null
                          ? null
                          : StooxWorkOrder.employeeIdFromSummary(employeeSummary),
                      allowMarkDone: true,
                      defaultMineFilter: true,
                    ),
                  ),
                );
                if (updated != null) onOrderUpdated?.call(updated);
              },
              icon: const Icon(Icons.list_alt),
              label: Text(
                order.works.isEmpty ? 'Список работ' : 'Список работ (${order.works.length})',
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: () {
                if (!_hasPlate(order, context)) return;
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CaptureScreen(
                      session: session,
                      order: order,
                      kind: 'inspection',
                      title: 'Осмотр',
                      employeeId: _employeeId(employeeSummary),
                      employeeName: employeeSummary == null
                          ? null
                          : StooxWorkOrder.employeeNameFromSummary(employeeSummary),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Осмотр'),
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: () {
                if (!_hasPlate(order, context)) return;
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CaptureScreen(
                      session: session,
                      order: order,
                      kind: 'diagnostics',
                      title: 'Диагностика',
                      employeeId: _employeeId(employeeSummary),
                      employeeName: employeeSummary == null
                          ? null
                          : StooxWorkOrder.employeeNameFromSummary(employeeSummary),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.build_circle_outlined),
              label: const Text('Диагностика'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AiChatScreen(
                      session: session,
                      order: order,
                      employeeId: _employeeId(employeeSummary),
                      employeeName: employeeSummary == null
                          ? null
                          : StooxWorkOrder.employeeNameFromSummary(employeeSummary),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.smart_toy_outlined),
              label: const Text('ИИ-чат'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

bool _hasPlate(StooxWorkOrder order, BuildContext context) {
  final plate = order.regNumber?.trim() ?? '';
  if (plate.length >= 5) return true;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('У авто нет госномера')),
  );
  return false;
}

Future<void> _showClientNotes(BuildContext context, StooxWorkOrder order) {
  final reason = order.shReason;
  final note = order.shNote;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final bottom = MediaQuery.paddingOf(ctx).bottom;
      return Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 16 + bottom),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Причина и заметка',
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                order.regNumber ?? order.saleNumber,
                style: const TextStyle(color: Colors.black54),
              ),
              if (reason != null && reason.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Причина (со слов клиента)', style: Theme.of(ctx).textTheme.titleSmall),
                const SizedBox(height: 6),
                Text(reason, style: const TextStyle(height: 1.4)),
              ],
              if (note != null && note.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Заметка', style: Theme.of(ctx).textTheme.titleSmall),
                const SizedBox(height: 6),
                Text(note, style: const TextStyle(height: 1.4)),
              ],
              const SizedBox(height: 12),
            ],
          ),
        ),
      );
    },
  );
}

int? _employeeId(Map<String, dynamic>? summary) {
  if (summary == null) return null;
  final raw = StooxWorkOrder.employeeIdFromSummary(summary);
  return raw == null ? null : int.tryParse(raw);
}

Future<StooxWorkOrder> _resolveWorkOrder({
  required StooxWorkOrder order,
  required StooxApi client,
  Map<String, dynamic>? employeeSummary,
  List<dynamic> sales = const [],
  List<dynamic> warranty = const [],
}) async {
  final dash = await client.fetchEmployeeDashboard();
  final summary = employeeSummary ?? dash.summary;
  final enriched = await client.enrichBasketItems(
    [order.raw],
    sales: sales.isNotEmpty ? sales : dash.sales,
    warranty: warranty.isNotEmpty ? warranty : dash.warranty,
    employeeSummary: summary,
  );
  if (enriched.isNotEmpty && enriched.first is Map) {
    return StooxWorkOrder(Map<String, dynamic>.from(enriched.first as Map));
  }
  return order;
}
