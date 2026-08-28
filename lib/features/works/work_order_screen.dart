import 'package:flutter/material.dart';

import '../../core/work_order.dart';

class WorkOrderScreen extends StatelessWidget {
  const WorkOrderScreen({
    super.key,
    required this.order,
    this.sectionTitle = 'Работы заказ-наряда',
  });

  final StooxWorkOrder order;
  final String sectionTitle;

  @override
  Widget build(BuildContext context) {
    final o = order;
    return Scaffold(
      appBar: AppBar(title: Text(sectionTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(o.saleNumber, style: Theme.of(context).textTheme.titleLarge),
                  if (o.regNumber != null) ...[
                    const SizedBox(height: 4),
                    Text('Госномер: ${o.regNumber}', style: const TextStyle(fontSize: 15)),
                  ],
                  if (o.mark != null || o.model != null) ...[
                    const SizedBox(height: 4),
                    Text('${o.mark ?? ''} ${o.model ?? ''}'.trim()),
                  ],
                  if (o.clientBalance != null || o.clientBalanceJur != null) ...[
                    const SizedBox(height: 8),
                    if (o.clientBalance != null)
                      Text('Баланс: ${StooxFormat.money(o.clientBalance!)}'),
                    if (o.clientBalanceJur != null)
                      Text('Баланс (юр.): ${StooxFormat.money(o.clientBalanceJur!)}'),
                  ],
                  if (o.employee != null)
                    Text('Исполнитель: ${o.employee}', style: const TextStyle(color: Colors.black54)),
                  if (o.createdAt != null)
                    Text('Дата: ${o.createdAt}', style: const TextStyle(color: Colors.black54)),
                  if (o.totalSum != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Итого: ${StooxFormat.money(o.totalSum!)}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _LinesSection(title: 'Работы', items: o.works, emptyText: 'Нет работ в ЗН'),
          if (o.parts.isNotEmpty) ...[
            const SizedBox(height: 12),
            _LinesSection(title: 'Запчасти', items: o.parts, emptyText: ''),
          ],
          if (o.cleaning.isNotEmpty) ...[
            const SizedBox(height: 12),
            _LinesSection(title: 'Клининг', items: o.cleaning, emptyText: ''),
          ],
        ],
      ),
    );
  }
}

class _LinesSection extends StatelessWidget {
  const _LinesSection({
    required this.title,
    required this.items,
    required this.emptyText,
  });

  final String title;
  final List<StooxLineItem> items;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty && emptyText.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (items.isEmpty)
              Text(emptyText, style: const TextStyle(color: Colors.black54))
            else
              ...items.map((item) => _LineTile(item: item)),
          ],
        ),
      ),
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({required this.item});

  final StooxLineItem item;

  @override
  Widget build(BuildContext context) {
    final price = item.unitPrice;
    final total = item.lineTotal;
    final qty = item.qty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: const TextStyle(fontSize: 14)),
                if (qty != 1 || price != null)
                  Text(
                    [
                      if (qty != 1) '${StooxFormat.qty(qty)} шт.',
                      if (price != null) '${StooxFormat.money(price)} / ед.',
                    ].join(' · '),
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
              ],
            ),
          ),
          if (total != null)
            Text(
              StooxFormat.money(total),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
        ],
      ),
    );
  }
}
