import 'package:flutter/material.dart';

class StatusBadge extends StatelessWidget {
  final String label;
  final Color? color;
  final IconData? icon;
  final bool isOutlined;

  const StatusBadge({
    super.key,
    required this.label,
    this.color,
    this.icon,
    this.isOutlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveColor = color ?? theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isOutlined
            ? Colors.transparent
            : effectiveColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isOutlined
              ? theme.colorScheme.outlineVariant
              : effectiveColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: effectiveColor),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: effectiveColor,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
