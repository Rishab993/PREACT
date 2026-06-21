import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/colors.dart';
import '../../providers/app_providers.dart';

/// Floating theme toggle button (dark/light)
class ThemeToggle extends ConsumerWidget {
  const ThemeToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(themeProvider) == ThemeMode.dark;
    return Tooltip(
      message: isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
      child: InkWell(
        onTap: () => ref.read(themeProvider.notifier).toggle(),
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceElevatedDark : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: isDark ? AppColors.borderDark : AppColors.borderLight,
            ),
          ),
          child: Icon(
            isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            size: 18,
            color: isDark ? const Color(0xFF2563EB) : AppColors.textSecondaryDark,
          ),
        ),
      ),
    );
  }
}

/// Language toggle (EN / ಕನ್ನಡ)
class LanguageToggle extends ConsumerWidget {
  const LanguageToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isKn = ref.watch(languageProvider).isKannada;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: isKn ? 'Switch to English' : 'ಕನ್ನಡಕ್ಕೆ ಬದಲಿಸಿ',
      child: InkWell(
        onTap: () => ref.read(languageProvider.notifier).toggle(),
        borderRadius: BorderRadius.circular(24),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: isKn
                ? const Color(0xFF2563EB).withOpacity(0.12)
                : (isDark ? AppColors.surfaceElevatedDark : AppColors.surfaceElevatedLight),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isKn
                  ? const Color(0xFF2563EB).withOpacity(0.4)
                  : (isDark ? AppColors.borderDark : AppColors.borderLight),
            ),
          ),
          child: Center(
            child: Text(
              isKn ? 'ಕನ್ನಡ' : 'EN',
              style: TextStyle(
                color: isKn
                    ? const Color(0xFF2563EB)
                    : (isDark ? AppColors.textSecondary : AppColors.textSecondaryDark),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

