import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onChanged,
  });

  final int currentIndex;
  final ValueChanged<int> onChanged;

  static const _items = [
    _NavItemData('Home', Icons.home_outlined, Icons.home_rounded),
    _NavItemData('Devices', Icons.memory_outlined, Icons.memory_rounded),
    _NavItemData(
        'Records', Icons.video_library_outlined, Icons.video_library_rounded),
    _NavItemData(
        'Camera', Icons.photo_camera_outlined, Icons.photo_camera_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.black,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              for (var index = 0; index < _items.length; index++)
                Expanded(
                  child: _BottomNavButton(
                    item: _items[index],
                    selected: currentIndex == index,
                    onTap: () => onChanged(index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNavButton extends StatelessWidget {
  const _BottomNavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _NavItemData item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accent : AppColors.muted;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? item.selectedIcon : item.icon,
                color: color, size: 25),
            const SizedBox(height: 5),
            Text(
              item.label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: color,
                    fontSize: 11,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItemData {
  const _NavItemData(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
