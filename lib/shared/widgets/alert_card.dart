import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';
import '../models/models.dart';

/// Severity-colored alert card with left border strip
class AlertCard extends StatelessWidget {
  final AlertModel alert;
  final VoidCallback? onTap;
  final VoidCallback? onDismiss;
  final bool showZone;

  const AlertCard({
    super.key,
    required this.alert,
    this.onTap,
    this.onDismiss,
    this.showZone = true,
  });

  Color get _severityColor {
    if (alert.severity >= 0.8) return AppColors.red;
    if (alert.severity >= 0.6) return AppColors.amber;
    if (alert.severity >= 0.4) return const Color(0xFF2563EB);
    return AppColors.green;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Dismissible(
      key: Key(alert.id),
      direction: onDismiss != null
          ? DismissDirection.endToStart
          : DismissDirection.none,
      onDismissed: (_) => onDismiss?.call(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppColors.red.withValues(alpha: 0.2),
        child: const Icon(Icons.delete_outline, color: AppColors.red),
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? AppColors.borderDark : AppColors.borderLight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (showZone) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _severityColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        alert.zone,
                        style: TextStyle(
                          color: _severityColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _severityColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _severityColor.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      alert.severityLabel(),
                      style: TextStyle(
                        color: _severityColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  if (alert.timeAgo.isNotEmpty)
                    Text(
                      alert.timeAgo,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (alert.title != null && alert.title!.isNotEmpty) ...[
                Text(
                  alert.title!,
                  style: TextStyle(
                    color: isDark ? AppColors.textPrimary : AppColors.textPrimaryDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
              ],
              Text(
                alert.messageEn ?? 'Alert for ${alert.zone}',
                style: TextStyle(
                  color: isDark
                      ? (alert.title != null ? AppColors.textSecondary : AppColors.textPrimary)
                      : (alert.title != null ? AppColors.textSecondaryDark : AppColors.textPrimaryDark),
                  fontSize: alert.title != null ? 12 : 14,
                  fontWeight: alert.title != null ? FontWeight.normal : FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (alert.validUntil != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Valid until ${alert.validUntil!.day.toString().padLeft(2, '0')}/${alert.validUntil!.month.toString().padLeft(2, '0')} ${alert.validUntil!.hour.toString().padLeft(2, '0')}:${alert.validUntil!.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (alert.category != null || alert.issuer != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (alert.category != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _severityColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: _severityColor.withValues(alpha: 0.25)),
                        ),
                        child: Text(
                          alert.category!.toUpperCase().replaceAll('_', ' '),
                          style: TextStyle(color: _severityColor, fontSize: 9, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    if (alert.issuer != null)
                      Flexible(
                        child: Text(
                          alert.issuer!,
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
