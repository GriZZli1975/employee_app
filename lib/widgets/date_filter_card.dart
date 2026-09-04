import 'package:flutter/material.dart';

enum DatePreset { day, week, month, custom }

class DateFilterCard extends StatelessWidget {
  const DateFilterCard({
    super.key,
    required this.dateFrom,
    required this.dateTo,
    required this.onPickFrom,
    required this.onPickTo,
    this.preset = DatePreset.month,
    this.onPreset,
    this.loading = false,
  });

  final String dateFrom;
  final String dateTo;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;
  final DatePreset preset;
  final ValueChanged<DatePreset>? onPreset;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_month_outlined, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text('Период', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                if (loading)
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                _PresetChip(label: 'День', selected: preset == DatePreset.day, onTap: loading ? null : () => onPreset?.call(DatePreset.day)),
                _PresetChip(label: 'Неделя', selected: preset == DatePreset.week, onTap: loading ? null : () => onPreset?.call(DatePreset.week)),
                _PresetChip(label: 'Месяц', selected: preset == DatePreset.month, onTap: loading ? null : () => onPreset?.call(DatePreset.month)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _DateChip(label: 'С', value: dateFrom, onTap: loading ? null : onPickFrom)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.arrow_forward, size: 16, color: scheme.outline),
                ),
                Expanded(child: _DateChip(label: 'По', value: dateTo, onTap: loading ? null : onPickTo)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({required this.label, required this.selected, this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: onTap == null ? null : (_) => onTap!(),
      selectedColor: scheme.primaryContainer,
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({required this.label, required this.value, this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}
