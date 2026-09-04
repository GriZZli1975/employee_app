import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/session.dart';
import '../../core/stoox_api.dart';
import '../../core/work_order.dart';
import '../../widgets/date_filter_card.dart';
import 'period_orders_screen.dart';

class ZnTabScreen extends StatefulWidget {
  const ZnTabScreen({super.key, required this.session});

  final EmployeeSession session;

  @override
  State<ZnTabScreen> createState() => ZnTabScreenState();
}

class ZnTabScreenState extends State<ZnTabScreen> {
  static final _dateFmt = DateFormat('dd.MM.yyyy');

  late DateTime _dateFrom;
  late DateTime _dateTo;
  DatePreset _preset = DatePreset.month;
  bool _loading = false;
  String? _error;
  List<StooxWorkOrder> _sales = [];
  List<StooxWorkOrder> _warranty = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _preset = DatePreset.month;
    _dateFrom = DateTime(now.year, now.month, 1);
    _dateTo = now;
    reload();
  }

  void _applyPreset(DatePreset preset, {bool reloadAfter = true}) {
    final now = DateTime.now();
    DateTime from = _dateFrom;
    DateTime to = _dateTo;
    switch (preset) {
      case DatePreset.day:
        from = DateTime(now.year, now.month, now.day);
        to = now;
      case DatePreset.week:
        from = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
        to = now;
      case DatePreset.month:
        from = DateTime(now.year, now.month, 1);
        to = now;
      case DatePreset.custom:
        break;
    }
    setState(() {
      _preset = preset;
      _dateFrom = from;
      _dateTo = to;
    });
    if (reloadAfter) reload();
  }

  Future<void> reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dash = await StooxApi(widget.session).fetchEmployeeDashboard(
        dateFrom: _dateFrom,
        dateTo: _dateTo,
      );
      if (!mounted) return;
      setState(() {
        _sales = dash.sales
            .whereType<Map>()
            .map((e) => StooxWorkOrder(Map<String, dynamic>.from(e)))
            .toList()
          ..sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
        _warranty = dash.warranty
            .whereType<Map>()
            .map((e) => StooxWorkOrder(Map<String, dynamic>.from(e)))
            .toList()
          ..sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate({required bool from}) async {
    final initial = from ? _dateFrom : _dateTo;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      _preset = DatePreset.custom;
      if (from) {
        _dateFrom = picked;
      } else {
        _dateTo = picked;
      }
    });
    reload();
  }

  void _openList({required String title, required List<StooxWorkOrder> orders, required String emptyText}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PeriodOrdersScreen(
          title: title,
          orders: orders,
          emptyText: emptyText,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: reload,
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          DateFilterCard(
            dateFrom: _dateFmt.format(_dateFrom),
            dateTo: _dateFmt.format(_dateTo),
            preset: _preset,
            onPreset: _applyPreset,
            onPickFrom: () => _pickDate(from: true),
            onPickTo: () => _pickDate(from: false),
            loading: _loading,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Material(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text('Заказ-наряды', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _loading
                ? null
                : () => _openList(
                      title: 'ЗН за период',
                      orders: _sales,
                      emptyText: 'Нет ЗН за выбранный период',
                    ),
            icon: const Icon(Icons.receipt_long_outlined),
            label: Text('ЗН за период (${_sales.length})'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _loading
                ? null
                : () => _openList(
                      title: 'Гарантийные ЗН',
                      orders: _warranty,
                      emptyText: 'Нет гарантийных ЗН за выбранный период',
                    ),
            icon: const Icon(Icons.verified_outlined),
            label: Text('Гарантийные ЗН (${_warranty.length})'),
          ),
        ],
      ),
    );
  }
}
