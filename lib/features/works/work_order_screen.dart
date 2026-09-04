import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/session.dart';
import '../../core/stoox_api.dart';
import '../../core/work_order.dart';

class WorkOrderScreen extends StatefulWidget {
  const WorkOrderScreen({
    super.key,
    required this.order,
    this.session,
    this.allowMarkDone = false,
    this.sectionTitle = 'Работы заказ-наряда',
  });

  final StooxWorkOrder order;
  final EmployeeSession? session;
  final bool allowMarkDone;
  final String sectionTitle;

  @override
  State<WorkOrderScreen> createState() => _WorkOrderScreenState();
}

class _WorkOrderScreenState extends State<WorkOrderScreen> {
  late List<StooxLineItem> _works;

  @override
  void initState() {
    super.initState();
    _works = List<StooxLineItem>.from(widget.order.works);
  }

  bool get _canMark => widget.allowMarkDone && widget.session != null;

  Future<void> _setWorkshop(StooxLineItem item, bool toWorkshop) async {
    final id = item.basketWorkId;
    final session = widget.session;
    if (id == null || session == null) {
      throw StooxApiException(0, 'Нет id работы в корзине');
    }
    await StooxApi(session).updateBasketWork(basketWorkId: id, toWorkshop: toWorkshop);
    if (!mounted) return;
    setState(() {
      _works = [
        for (final w in _works)
          w.basketWorkId == id ? w.withToWorkshop(toWorkshop) : w,
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.sectionTitle)),
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
                    Text('Исполнитель: ${o.employee}', style: TextStyle(color: scheme.onSurfaceVariant)),
                  if (o.createdAt != null)
                    Text('Дата: ${o.createdAt}', style: TextStyle(color: scheme.onSurfaceVariant)),
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
          if (_canMark && _works.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Удерживайте работу 1 сек — карточка зальётся зелёным. Ещё раз удержать — снять отметку.',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant, height: 1.35),
              ),
            ),
          _WorksSection(
            items: _works,
            emptyText: 'Нет работ в ЗН',
            canMark: _canMark,
            onCommit: _setWorkshop,
          ),
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

class _WorksSection extends StatelessWidget {
  const _WorksSection({
    required this.items,
    required this.emptyText,
    required this.canMark,
    required this.onCommit,
  });

  final List<StooxLineItem> items;
  final String emptyText;
  final bool canMark;
  final Future<void> Function(StooxLineItem item, bool toWorkshop) onCommit;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(emptyText, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text('Работы', style: Theme.of(context).textTheme.titleMedium),
        ),
        for (final item in items) ...[
          _HoldWorkCard(
            key: ValueKey(item.basketWorkId ?? item.name),
            item: item,
            enabled: canMark && item.basketWorkId != null,
            onCommit: (done) => onCommit(item, done),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _HoldWorkCard extends StatefulWidget {
  const _HoldWorkCard({
    super.key,
    required this.item,
    required this.enabled,
    required this.onCommit,
  });

  final StooxLineItem item;
  final bool enabled;
  final Future<void> Function(bool toWorkshop) onCommit;

  @override
  State<_HoldWorkCard> createState() => _HoldWorkCardState();
}

class _HoldWorkCardState extends State<_HoldWorkCard> with SingleTickerProviderStateMixin {
  static const _hold = Duration(seconds: 1);
  static const _doneGreen = Color(0xFF2E7D32);

  late final AnimationController _holdCtrl;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _holdCtrl = AnimationController(vsync: this, duration: _hold);
    _holdCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _commit();
      }
    });
  }

  @override
  void dispose() {
    _holdCtrl.dispose();
    super.dispose();
  }

  void _startHold() {
    if (!widget.enabled || _busy) return;
    _holdCtrl.forward(from: 0);
  }

  void _cancelHold() {
    if (_busy) return;
    if (_holdCtrl.status == AnimationStatus.completed) return;
    _holdCtrl.reverse();
  }

  Future<void> _commit() async {
    if (_busy || !mounted) return;
    setState(() => _busy = true);
    final next = !widget.item.toWorkshop;
    try {
      await HapticFeedback.mediumImpact();
      await widget.onCommit(next);
      if (mounted) _holdCtrl.reset();
    } catch (e) {
      if (mounted) {
        _holdCtrl.reset();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = widget.item.toWorkshop;
    final price = widget.item.unitPrice;
    final total = widget.item.lineTotal;
    final qty = widget.item.qty;

    return AnimatedBuilder(
      animation: _holdCtrl,
      builder: (context, child) {
        final hold = _holdCtrl.value.clamp(0.0, 1.0);
        final fill = done ? (1.0 - hold) : hold;
        final filled = done && hold == 0;
        final bg = Color.lerp(scheme.surfaceContainerHighest, _doneGreen, fill) ?? _doneGreen;
        final fg = fill > 0.45 ? Colors.white : scheme.onSurface;
        final muted = fill > 0.45 ? Colors.white70 : scheme.onSurfaceVariant;

        return Material(
          color: bg,
          elevation: 1,
          borderRadius: BorderRadius.circular(14),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: widget.enabled ? (_) => _startHold() : null,
            onTapUp: widget.enabled ? (_) => _cancelHold() : null,
            onTapCancel: widget.enabled ? _cancelHold : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Row(
                  children: [
                    Icon(
                      filled || fill > 0.85 ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: fg,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.item.name,
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: fg),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            filled
                                ? 'Сделано'
                                : widget.enabled
                                    ? (hold > 0
                                        ? (done ? 'Удерживайте, чтобы снять' : 'Удерживайте…')
                                        : 'Удерживайте 1 сек')
                                    : [
                                        if (qty != 1) '${StooxFormat.qty(qty)} шт.',
                                        if (price != null) '${StooxFormat.money(price)} / ед.',
                                      ].join(' · '),
                            style: TextStyle(fontSize: 12, color: muted),
                          ),
                        ],
                      ),
                    ),
                    if (total != null)
                      Text(
                        StooxFormat.money(total),
                        style: TextStyle(fontWeight: FontWeight.w700, color: fg),
                      ),
                    if (_busy) ...[
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
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
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (items.isEmpty)
              Text(emptyText, style: TextStyle(color: muted))
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
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
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
                    style: TextStyle(fontSize: 12, color: muted),
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
