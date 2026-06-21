import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/colors.dart';
import '../../providers/app_providers.dart';
import 'app_toggles.dart';
import 'brand_logo.dart';
import 'app_footer.dart';

// ── Navigation destinations ───────────────────────────────────────────────────
const _citizenNavItems = [
  _NavItem(icon: Icons.dashboard_outlined,    activeIcon: Icons.dashboard,         label: 'Dashboard',    labelKn: 'ಡ್ಯಾಶ್‌ಬೋರ್ಡ್'),
  _NavItem(icon: Icons.notifications_outlined,activeIcon: Icons.notifications,      label: 'Alerts',       labelKn: 'ಎಚ್ಚರಿಕೆಗಳು'),
  _NavItem(icon: Icons.report_gmailerrorred_outlined, activeIcon: Icons.report, label: 'Raise Complaint', labelKn: 'ದೂರು ಸಲ್ಲಿಸಿ'),
  _NavItem(icon: Icons.volunteer_activism_outlined, activeIcon: Icons.volunteer_activism, label: 'Volunteer Signup', labelKn: 'ಸ್ವಯಂಸೇವಕ ದಾಖಲಾತಿ'),
  _NavItem(icon: Icons.mic_outlined,          activeIcon: Icons.mic,                label: 'Voice',        labelKn: 'ಧ್ವನಿ'),
];

const _policeNavItems = [
  _NavItem(icon: Icons.dashboard_outlined,    activeIcon: Icons.dashboard,         label: 'Dashboard',    labelKn: 'ಡ್ಯಾಶ್‌ಬೋರ್ಡ್'),
  _NavItem(icon: Icons.notifications_outlined,activeIcon: Icons.notifications,      label: 'Alerts',       labelKn: 'ಎಚ್ಚರಿಕೆಗಳು'),
  _NavItem(icon: Icons.report_gmailerrorred_outlined, activeIcon: Icons.report, label: 'Complaint Review', labelKn: 'ದೂರು ಪರಿಶೀಲನೆ'),
  _NavItem(icon: Icons.volunteer_activism_outlined, activeIcon: Icons.volunteer_activism, label: 'Volunteer Approvals', labelKn: 'ಸ್ವಯಂಸೇವಕ ಅನುಮೋದನೆ'),
  _NavItem(icon: Icons.bar_chart_outlined,    activeIcon: Icons.bar_chart,          label: 'Forecast',     labelKn: 'ಮುನ್ಸೂಚನೆ'),
  _NavItem(icon: Icons.people_alt_outlined,   activeIcon: Icons.people_alt,         label: 'Deployment',   labelKn: 'ನಿಯೋಜನೆ'),
  _NavItem(icon: Icons.science_outlined,      activeIcon: Icons.science,            label: 'Simulation',   labelKn: 'ಸಿಮ್ಯುಲೇಟರ್'),
  _NavItem(icon: Icons.compare_outlined,      activeIcon: Icons.compare,            label: 'Shadow Ops',   labelKn: 'ಶಾಡೋ'),
  _NavItem(icon: Icons.fact_check_outlined,   activeIcon: Icons.fact_check,         label: 'Ground Truth', labelKn: 'ನೆಲ ಸತ್ಯ'),
  _NavItem(icon: Icons.history_edu_outlined,  activeIcon: Icons.history_edu,        label: 'Memory',       labelKn: 'ಸ್ಮರಣೆ'),
  _NavItem(icon: Icons.mic_outlined,          activeIcon: Icons.mic,                label: 'Voice',        labelKn: 'ಧ್ವನಿ'),
];

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String labelKn;
  const _NavItem({
    required this.icon, required this.activeIcon,
    required this.label, required this.labelKn,
  });
}

class AppShell extends ConsumerWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 900;

    if (isWide) {
      return _DesktopShell(child: child);
    } else {
      return _MobileShell(child: child);
    }
  }
}

class _DesktopShell extends ConsumerWidget {
  final Widget child;
  const _DesktopShell({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(roleProvider);
    final selectedIndex = ref.watch(navIndexProvider);
    final isKn = ref.watch(languageProvider).isKannada;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final navItems = role == AppRole.citizen ? _citizenNavItems : _policeNavItems;
    final clampedIndex = selectedIndex.clamp(0, navItems.length - 1);

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(76),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            border: Border(
              bottom: BorderSide(
                color: isDark ? AppColors.borderDark : AppColors.borderLight,
                width: 1,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SafeArea(
            child: Row(
              children: [
                const BrandLogo.compact(),
                const Spacer(),
                // Role indicator badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: role == AppRole.citizen 
                        ? const Color(0xFF2563EB).withOpacity(0.12)
                        : const Color(0xFFFFAA00).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: role == AppRole.citizen 
                          ? const Color(0xFF2563EB).withOpacity(0.4)
                          : const Color(0xFFFFAA00).withOpacity(0.4),
                    ),
                  ),
                  child: Text(
                    role == AppRole.citizen 
                        ? (isKn ? 'ನಾಗರಿಕ' : 'CITIZEN') 
                        : (isKn ? 'ಪೊಲೀಸ್' : 'POLICE'),
                    style: TextStyle(
                      color: role == AppRole.citizen ? const Color(0xFF2563EB) : const Color(0xFFFFAA00),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                const ThemeToggle(),
                const SizedBox(width: 8),
                const LanguageToggle(),
                const SizedBox(width: 16),
                // Switch Role — premium gradient button
                _SwitchRoleButton(
                  label: isKn ? 'ಪಾತ್ರ ಬದಲಿಸಿ' : 'Switch Role',
                  onTap: () {
                    ref.read(navIndexProvider.notifier).state = 0;
                    ref.read(roleProvider.notifier).reset();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 220,
                  color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    itemCount: navItems.length,
                    itemBuilder: (_, i) {
                      final item = navItems[i];
                      final selected = i == clampedIndex;
                      return _SidebarItem(
                        icon: selected ? item.activeIcon : item.icon,
                        label: isKn ? item.labelKn : item.label,
                        selected: selected,
                        onTap: () => ref.read(navIndexProvider.notifier).state = i,
                      );
                    },
                  ),
                ),
                VerticalDivider(width: 1, color: isDark ? AppColors.borderDark : AppColors.borderLight),
                Expanded(child: child),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: const AppFooter(),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon, required this.label,
    required this.selected, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF2563EB).withOpacity(0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: selected
            ? Border.all(color: const Color(0xFF2563EB).withOpacity(0.3))
            : null,
      ),
      child: ListTile(
        dense: true,
        leading: Icon(
          icon,
          size: 20,
          color: selected ? const Color(0xFF2563EB) : (isDark ? AppColors.textSecondary : AppColors.textSecondaryDark),
        ),
        title: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF2563EB) : (isDark ? AppColors.textSecondary : AppColors.textSecondaryDark),
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        minLeadingWidth: 24,
      ),
    );
  }
}

class _MobileShell extends ConsumerWidget {
  final Widget child;
  const _MobileShell({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(roleProvider);
    final navIndex = ref.watch(navIndexProvider);
    final isKn = ref.watch(languageProvider).isKannada;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final navItems = role == AppRole.citizen ? _citizenNavItems : _policeNavItems;
    final clampedIndex = navIndex.clamp(0, navItems.length - 1);
    final activeItem = navItems[clampedIndex];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isKn ? activeItem.labelKn : activeItem.label,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          const ThemeToggle(),
          const SizedBox(width: 4),
          const LanguageToggle(),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _SwitchRoleButton(
              label: isKn ? 'ಪಾತ್ರ ಬದಲಿಸಿ' : 'Switch',
              compact: true,
              onTap: () {
                ref.read(navIndexProvider.notifier).state = 0;
                ref.read(roleProvider.notifier).reset();
              },
            ),
          ),
        ],
      ),
      drawer: Drawer(
        child: Column(
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                border: Border(bottom: BorderSide(color: isDark ? AppColors.borderDark : AppColors.borderLight)),
              ),
              child: const Align(
                alignment: Alignment.centerLeft,
                child: BrandLogo.compact(),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                itemCount: navItems.length,
                itemBuilder: (_, i) {
                  final item = navItems[i];
                  final selected = i == clampedIndex;
                  return ListTile(
                    leading: Icon(
                      selected ? item.activeIcon : item.icon,
                      color: selected ? const Color(0xFF2563EB) : (isDark ? AppColors.textSecondary : AppColors.textSecondaryDark),
                    ),
                    title: Text(
                      isKn ? item.labelKn : item.label,
                      style: TextStyle(
                        color: selected ? const Color(0xFF2563EB) : (isDark ? AppColors.textPrimary : AppColors.textPrimaryDark),
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    selected: selected,
                    onTap: () {
                      ref.read(navIndexProvider.notifier).state = i;
                      Navigator.pop(context); // close drawer
                    },
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  );
                },
              ),
            ),

          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(child: child),
          SafeArea(
            top: false,
            child: const AppFooter(),
          ),
        ],
      ),
    );
  }
}

// ── Premium Switch Role Button ────────────────────────────────────────────────
class _SwitchRoleButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool compact;

  const _SwitchRoleButton({
    required this.label,
    required this.onTap,
    this.compact = false,
  });

  @override
  State<_SwitchRoleButton> createState() => _SwitchRoleButtonState();
}

class _SwitchRoleButtonState extends State<_SwitchRoleButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: widget.compact
              ? const EdgeInsets.symmetric(horizontal: 10, vertical: 7)
              : const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xFF1E3A5F),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hovered ? const Color(0xFF2563EB) : const Color(0xFF1E3A5F),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedRotation(
                turns: _hovered ? 0.5 : 0.0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: const Icon(
                  Icons.swap_horiz_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              if (!widget.compact) ...[
                const SizedBox(width: 6),
                Text(
                  widget.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
