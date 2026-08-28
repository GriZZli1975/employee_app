import 'package:flutter/material.dart';

/// Нижнее меню: ЗН · В работе (центр) · Личное.
class MainNavBar extends StatelessWidget {
  const MainNavBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const inWorkTabIndex = 1;

  static const labels = ['ЗН', 'В работе', 'Личное'];
  static const icons = [
    Icons.receipt_long_outlined,
    Icons.directions_car_outlined,
    Icons.person_outline,
  ];
  static const selectedIcons = [
    Icons.receipt_long,
    Icons.directions_car,
    Icons.person,
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: List.generate(3, (i) {
              final isCenter = i == inWorkTabIndex;
              final selected = selectedIndex == i;
              final color = selected ? scheme.primary : Colors.black54;

              if (isCenter) {
                return Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Material(
                      color: selected ? scheme.primary : scheme.primary.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(20),
                      elevation: selected ? 4 : 2,
                      child: InkWell(
                        onTap: () => onSelected(i),
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                selected ? selectedIcons[i] : icons[i],
                                color: Colors.white,
                                size: 26,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                labels[i],
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }

              return Expanded(
                child: InkWell(
                  onTap: () => onSelected(i),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          selected ? selectedIcons[i] : icons[i],
                          color: color,
                          size: 20,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          labels[i],
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                            color: color,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
