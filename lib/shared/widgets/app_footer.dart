import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';

/// Dataset attribution footer shown on all screen sizes.
class AppFooter extends StatelessWidget {
  const AppFooter({super.key});

  static const String text =
      'All datasets used for displayed information, analytics and forecasting '
      'were derived from the provided AstraM traffic management dataset for '
      'the respective police station.';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
          ),
        ),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: isDark ? AppColors.textMuted : AppColors.textSecondaryDark,
          fontSize: 11,
          height: 1.4,
        ),
      ),
    );
  }
}
