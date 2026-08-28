import 'package:flutter/material.dart';

import '../../core/work_order.dart';
import 'work_order_screen.dart';

/// Список заказ-нарядов (продажи или гарантия) за период по клиенту/авто.
class PeriodOrdersScreen extends StatelessWidget {
  const PeriodOrdersScreen({
    super.key,
    required this.title,
    required this.orders,
    this.emptyText = 'За выбранный период записей нет',
  });

  final String title;
  final List<StooxWorkOrder> orders;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: orders.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(emptyText, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: orders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final order = orders[index];
                return Card(
                  child: ListTile(
                    title: Text(order.saleNumber, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      [
                        if (order.regNumber != null) order.regNumber,
                        if (order.createdAt != null) order.createdAt,
                        if (order.totalSum != null) StooxFormat.money(order.totalSum!),
                      ].whereType<String>().join(' · '),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => WorkOrderScreen(
                            order: order,
                            sectionTitle: title,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }

  static List<StooxWorkOrder> filterForOrder(
    List<dynamic> catalog,
    StooxWorkOrder anchor, {
    bool excludeCurrentSale = true,
  }) {
    final out = <StooxWorkOrder>[];
    final seen = <String>{};
    for (final item in catalog) {
      if (item is! Map) continue;
      final order = StooxWorkOrder(Map<String, dynamic>.from(item));
      if (!_matchesAnchor(order, anchor)) continue;
      if (excludeCurrentSale && _sameSale(order, anchor)) continue;
      final key = order.saleId?.toString() ?? order.saleNumber;
      if (!seen.add(key)) continue;
      out.add(order);
    }
    out.sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
    return out;
  }

  static bool _matchesAnchor(StooxWorkOrder candidate, StooxWorkOrder anchor) {
    if (anchor.clientId != null && candidate.clientId == anchor.clientId) return true;
    final plateA = anchor.regNumber?.trim().toUpperCase();
    final plateB = candidate.regNumber?.trim().toUpperCase();
    if (plateA != null && plateA.length >= 5 && plateA == plateB) return true;
    return false;
  }

  static bool _sameSale(StooxWorkOrder a, StooxWorkOrder b) {
    if (a.saleId != null && b.saleId != null && a.saleId == b.saleId) return true;
    return a.saleNumber == b.saleNumber && a.saleNumber != '—';
  }
}
