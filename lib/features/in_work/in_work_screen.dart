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
      final patched = [
        for (final item in _items)
          if (item is Map && StooxApi.basketMergeKey(Map<String, dynamic>.from(item)) == key)
            updated.raw
          else
            item,
      ];
      _items = StooxWorkOrder.sortOpenBaskets(patched);
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
      final items = StooxWorkOrder.sortOpenBaskets(
        await client.enrichBasketItems(
          dash.baskets,
          sales: dash.sales,
          warranty: dash.warranty,
          employeeSummary: dash.summary,
          openOnly: true,
        ),
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
    final scheme = Theme.of(context).colorScheme;
    final groups = StooxWorkOrder.groupByPlanningDay(_items);
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
            'По дням записи: время на карточке, дата — на линейке слева.',
            style: TextStyle(color: Colors.black54, height: 1.35),
          ),
          const SizedBox(height: 16),
          if (_loading) const LinearProgressIndicator(minHeight: 3),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Material(
              color: scheme.errorContainer,
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
            for (var gi = 0; gi < groups.length; gi++) ...[
              _DayTimelineSection(
                day: groups[gi].day,
                count: groups[gi].orders.length,
                isLast: gi == groups.length - 1,
                child: Column(
                  children: [
                    for (final order in groups[gi].orders)
                      _CarTile(
                        order: order,
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
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }
}

class _DayTimelineSection extends StatelessWidget {
  const _DayTimelineSection({
    required this.day,
    required this.count,
    required this.isLast,
    required this.child,
  });

  final DateTime? day;
  final int count;
  final bool isLast;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final overdueDay = day != null && day!.isBefore(today);
    final isToday = day != null && day == today;

    final label = day == null
        ? 'Без записи'
        : isToday
            ? 'Сегодня · ${_fmtDay(day!)}'
            : _fmtDay(day!);

    final accent = overdueDay
        ? scheme.error
        : isToday
            ? scheme.primary
            : scheme.outline;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 56,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.surface, width: 2),
                    boxShadow: [
                      BoxShadow(color: accent.withValues(alpha: 0.35), blurRadius: 4),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: isLast ? Colors.transparent : accent.withValues(alpha: 0.35),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: overdueDay ? scheme.error : scheme.onSurface,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '$count',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  child,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtDay(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd.$mm';
  }
}

class _CarTile extends StatelessWidget {
  const _CarTile({required this.order, required this.onTap});

  final StooxWorkOrder order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final overdue = order.isPlanningOverdue;
    final time = order.planningTimeLabel;
    final subtitleParts = <String>[
      if (time != null && time.isNotEmpty) time,
      if (order.mark != null) '${order.mark} ${order.model ?? ''}'.trim(),
      '${order.works.length} работ',
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: overdue ? scheme.errorContainer.withValues(alpha: 0.45) : null,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              backgroundColor: overdue
                  ? scheme.error.withValues(alpha: 0.15)
                  : scheme.primary.withValues(alpha: 0.12),
              child: Icon(
                Icons.directions_car,
                color: overdue ? scheme.error : scheme.primary,
              ),
            ),
            if (overdue)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: scheme.error,
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.surface, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
        title: Text(
          order.regNumber ?? order.saleNumber,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: overdue ? scheme.error : null,
          ),
        ),
        subtitle: Text(
          [
            if (overdue) 'Просрочена',
            ...subtitleParts.where((s) => s.isNotEmpty),
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: overdue ? scheme.error.withValues(alpha: 0.9) : null,
            height: 1.3,
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
