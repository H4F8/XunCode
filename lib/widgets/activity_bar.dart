import 'package:flutter/material.dart';
import '../app/theme.dart';
import '../services/language_service.dart';

enum ActivityBarItem { explorer, search, extensions, settings }

class ActivityBar extends StatelessWidget {
  final ActivityBarItem selected;
  final ValueChanged<ActivityBarItem> onSelect;
  final bool settingsBadge;

  const ActivityBar({
    super.key,
    required this.selected,
    required this.onSelect,
    this.settingsBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.of(context);
    return Container(
      width: 48,
      color: VscodeTheme.activityBg,
      child: Column(
        children: [
          const SizedBox(height: 8),
          _item(ActivityBarItem.explorer, Icons.folder_outlined, lang.tr('activity.explorer')),
          _item(ActivityBarItem.search, Icons.search, lang.tr('activity.search')),
          _item(ActivityBarItem.extensions, Icons.extension_outlined, lang.tr('activity.extensions')),
          const Spacer(),
          _item(ActivityBarItem.settings, Icons.settings_outlined, lang.tr('activity.settings'),
              badge: settingsBadge),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _item(ActivityBarItem item, IconData icon, String tooltip,
      {bool badge = false}) {
    final isSelected = selected == item;
    return Tooltip(
      message: tooltip,
      preferBelow: false,
      child: InkWell(
        onTap: () => onSelect(item),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: isSelected ? VscodeTheme.accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(
                icon,
                size: 22,
                color: isSelected ? VscodeTheme.fg : VscodeTheme.fgMuted,
              ),
              if (badge)
                Positioned(
                  right: 9,
                  top: 9,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.red.shade600,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
