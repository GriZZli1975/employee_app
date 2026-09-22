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
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _works = List<StooxLineItem>.from(widget.order.works);
  }

  bool get _canMark => widget.allowMarkDone && widget.session != null;

  StooxWorkOrder get _currentOrder => widget.order.withWorks(_works);

  void _popWithOrder() {
    Navigator.of(context).pop(_dirty ? _currentOrder : null);
  }

  Future<void> _setWorkshop(StooxLineItem item, bool toWorkshop) async {
    final id = item.basketWorkId;
    final session = widget.session;
    if (id == null || session == null) {
      throw StooxApiException(0, 'Нет id работы в корзине');
    }
    await StooxApi(session).updateBasketWork(basketWorkId: id, toWorkshop: toWorkshop);
    if (!mounted) return;
    setState(() {
      _dirty = true;
      _works = [
        for (final w in _works)
          w.basketWorkId == id ? w.withToWorkshop(toWorkshop) : w,
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final o = _currentOrder;
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _popWithOrder();
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(widget.sectionTitle),
        leading: BackButton(onPressed: _popWithOrder),
      ),
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
                'Смахните работу в сторону — станет зелёной (сделано). Ещё раз смахнуть — снова серая.',
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
          _SwipeWorkCard(
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

class _SwipeWorkCard extends StatefulWidget {
  const _SwipeWorkCard({
    super.key,
    required this.item,
    required this.enabled,
    required this.onCommit,
  });

  final StooxLineItem item;
  final bool enabled;
  final Future<void> Function(bool toWorkshop) onCommit;

  @override
  State<_SwipeWorkCard> createState() => _SwipeWorkCardState();
}

class _SwipeWorkCardState extends State<_SwipeWorkCard> {
  static const _doneGreen = Color(0xFF2E7D32);
  bool _busy = false;

  Future<bool> _onSwipe(DismissDirection _) async {
    if (!widget.enabled || _busy) return false;
    setState(() => _busy = true);
    final next = !widget.item.toWorkshop;
    try {
      await HapticFeedback.mediumImpact();
      await widget.onCommit(next);
    } catch (e) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Статус не сохранился'),
            content: Text(e.toString()),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Понятно')),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    // false — карточку не удаляем, только переключаем цвет.
    return false;
  }

  Widget _swipeBg({required bool markDone, required Alignment align}) {
    return Container(
      alignment: align,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: markDone ? _doneGreen : Colors.blueGrey.shade400,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (align == Alignment.centerLeft) ...[
            Icon(markDone ? Icons.check_circle : Icons.undo, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              markDone ? 'Сделано' : 'Снять',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ] else ...[
            Text(
              markDone ? 'Сделано' : 'Снять',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            Icon(markDone ? Icons.check_circle : Icons.undo, color: Colors.white),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = widget.item.toWorkshop;
    final price = widget.item.unitPrice;
    final total = widget.item.lineTotal;
    final qty = widget.item.qty;
    final fg = done ? Colors.white : scheme.onSurface;
    final muted = done ? Colors.white70 : scheme.onSurfaceVariant;
    final markDone = !done;

    final card = Material(
      color: done ? _doneGreen : scheme.surfaceContainerHighest,
      elevation: 1,
      borderRadius: BorderRadius.circular(14),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              Icon(
                done ? Icons.check_circle : Icons.radio_button_unchecked,
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
                      done
                          ? 'Сделано · смахните, чтобы снять'
                          : widget.enabled
                              ? 'Смахните, чтобы отметить'
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
    );

    if (!widget.enabled) return card;

    return Dismissible(
      key: ValueKey('swipe-${widget.item.basketWorkId ?? widget.item.name}'),
      direction: _busy ? DismissDirection.none : DismissDirection.horizontal,
      confirmDismiss: _onSwipe,
      background: _swipeBg(markDone: markDone, align: Alignment.centerLeft),
      secondaryBackground: _swipeBg(markDone: markDone, align: Alignment.centerRight),
      child: card,
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
