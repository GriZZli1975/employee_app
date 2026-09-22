import 'package:flutter/material.dart';

import '../../core/session.dart';
import '../../core/stoox_api.dart';
import '../../core/work_order.dart';
import 'car_actions_sheet.dart';

class InWorkScreen extends StatefulWidget {
  const InWorkScreen({
    super.key,
    required this.session,
    this.onCountChanged,
  });

  final EmployeeSession session;
  final ValueChanged<int>? onCountChanged;

  @override
  State<InWorkScreen> createState() => InWorkScreenState();
}

class InWorkScreenState extends State<InWorkScreen> {
  bool _loading = false;
  String? _error;
  List<dynamic> _items = [];
  List<dynamic> _sales = [];
  List<dynamic> _warranty = [];
  Map<String, dynamic>? _employeeSummary;

  @override
  void initState() {
    super.initState();
    reload();
  }

  void _patchOrder(StooxWorkOrder updated) {
    final key = StooxApi.basketMergeKey(updated.raw);
    setState(() {
      _items = [
        for (final item in _items)
          if (item is Map && StooxApi.basketMergeKey(Map<String, dynamic>.from(item)) == key)
            updated.raw
          else
            item,
      ];
    });
  }

  Future<void> reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = StooxApi(widget.session);
      final dash = await client.fetchEmployeeDashboard();
      final items = await client.enrichBasketItems(
        dash.baskets,
        sales: dash.sales,
        warranty: dash.warranty,
        employeeSummary: dash.summary,
        openOnly: true,
      );
      if (mounted) {
        setState(() {
          _items = items;
          _sales = dash.sales;
          _warranty = dash.warranty;
          _employeeSummary = dash.summary;
        });
        widget.onCountChanged?.call(items.length);
      }
    } on StooxApiException catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: reload,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Text(
            'В работе',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Выберите авто: работы ЗН, осмотр или диагностика.',
            style: TextStyle(color: Colors.black54, height: 1.35),
          ),
          const SizedBox(height: 16),
          if (_loading) const LinearProgressIndicator(minHeight: 3),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Material(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!),
              ),
            ),
          ],
          const SizedBox(height: 8),
          if (!_loading && _items.isEmpty && _error == null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.directions_car_outlined, size: 48, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    const Text('Нет авто в работе', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    const Text(
                      'Когда Stoox назначит заказы — они появятся здесь.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._items.map((item) {
              if (item is! Map) return const SizedBox.shrink();
              final order = StooxWorkOrder(Map<String, dynamic>.from(item));
              final subtitleParts = <String>[
                if (order.mark != null) '${order.mark} ${order.model ?? ''}'.trim(),
                if (order.totalSum != null) StooxFormat.money(order.totalSum!),
                '${order.works.length} работ',
              ];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                    child: Icon(Icons.directions_car, color: Theme.of(context).colorScheme.primary),
                  ),
                  title: Text(
                    order.regNumber ?? order.saleNumber,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    subtitleParts.where((s) => s.isNotEmpty).join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showCarActions(
                    context: context,
                    session: widget.session,
                    order: order,
                    stocks: StooxApi(widget.session),
                    employeeSummary: _employeeSummary,
                    sales: _sales,
                    warranty: _warranty,
                    onOrderUpdated: _patchOrder,
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
