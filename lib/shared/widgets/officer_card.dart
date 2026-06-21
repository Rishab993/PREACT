import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';
import '../models/models.dart';

/// Officer card with avatar initial, name, badge, zone, shift
class OfficerCard extends StatelessWidget {
  final OfficerModel officer;
  final bool isSelected;
  final bool isVolunteer;
  final VoidCallback? onTap;

  const OfficerCard({
    super.key,
    required this.officer,
    this.isSelected = false,
    this.isVolunteer = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final zoneColor = AppColors.forZone(
      const Color(0xFF2563EB).hashCode % 10,
    );
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF2563EB)
                : isVolunteer
                    ? AppColors.amber
                    : (isDark ? AppColors.borderDark : AppColors.borderLight),
            width: isSelected || isVolunteer ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: const Color(0xFF2563EB).withOpacity(0.15), blurRadius: 12)]
              : null,
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: zoneColor.withOpacity(0.15),
                shape: BoxShape.circle,
                border: Border.all(color: zoneColor.withOpacity(0.4)),
              ),
              child: Center(
                child: Text(
                  officer.initials,
                  style: TextStyle(
                    color: zoneColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          officer.name,
                          style: TextStyle(
                            color: isDark ? AppColors.textPrimary : AppColors.textPrimaryDark,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isVolunteer)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.amber.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.amber.withOpacity(0.5)),
                          ),
                          child: const Text(
                            'VOL',
                            style: TextStyle(
                              color: AppColors.amber,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _badge(officer.badgeNumber, AppColors.textSecondary),
                      const SizedBox(width: 8),
                      _badge(officer.zone, zoneColor),
                    ],
                  ),
                  if (officer.shiftStart != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.schedule_outlined, size: 12, color: AppColors.textMuted),
                          const SizedBox(width: 4),
                          Text(
                            '${officer.shiftStart} – ${officer.shiftEnd}',
                            style: TextStyle(color: isDark ? AppColors.textMuted : AppColors.textSecondaryDark, fontSize: 11),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 6, height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: officer.available ? AppColors.green : AppColors.red,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            officer.available ? 'Available' : 'On duty',
                            style: TextStyle(
                              color: officer.available ? AppColors.green : AppColors.red,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w500)),
  );
}

/// Zone chip — colored badge for zone name
class ZoneChip extends StatelessWidget {
  final String zone;
  final double? severity;
  final VoidCallback? onTap;

  const ZoneChip({super.key, required this.zone, this.severity, this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = severity != null
        ? AppColors.fromSeverity(severity!)
        : const Color(0xFF2563EB);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Text(
          zone,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

