import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/app_providers.dart';
import 'shared/widgets/lazy_indexed_stack.dart';
import 'features/assistant/voice_assistant_overlay.dart';
import 'features/auth/role_selection_screen.dart';

// Screen imports
import 'features/dashboard/dashboard_screen.dart';
import 'features/forecast/forecast_screen.dart';
import 'features/deployment/deployment_screen.dart';
import 'features/shadow/shadow_screen.dart';
import 'features/complaints/complaints_screen.dart';
import 'features/alerts/alerts_screen.dart';
import 'features/simulator/simulator_screen.dart';
import 'features/ground_truth/ground_truth_screen.dart';
import 'features/volunteer/volunteer_screen.dart';
import 'features/memory/memory_screen.dart';
import 'shared/widgets/app_shell.dart';

class AppRouter extends ConsumerWidget {
  const AppRouter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(roleProvider);
    if (role == null) {
      return const RoleSelectionScreen();
    }

    final navIndex = ref.watch(navIndexProvider);
    final voiceOpen = ref.watch(voiceOverlayOpenProvider);
    final clampedIndex = navIndex;

    if (role == AppRole.citizen) {
      return Stack(
        children: [
          AppShell(
            child: LazyIndexedStack(
              index: clampedIndex,
              builders: [
                () => const DashboardScreen(),
                () => const AlertsScreen(),
                () => const ComplaintsScreen(),
                () => const VolunteerScreen(),
                () => const VoiceScreenWrapper(),
              ],
            ),
          ),
          if (voiceOpen) _voiceOverlay(ref),
        ],
      );
    }

    return Stack(
      children: [
        AppShell(
          child: LazyIndexedStack(
            index: clampedIndex,
            builders: [
              () => const DashboardScreen(),
              () => const AlertsScreen(),
              () => const ComplaintsScreen(),
              () => const VolunteerScreen(),
              () => const ForecastScreen(),
              () => const DeploymentScreen(),
              () => const SimulatorScreen(),
              () => const ShadowScreen(),
              () => const GroundTruthScreen(),
              () => const MemoryScreen(),
              () => const VoiceScreenWrapper(),
            ],
          ),
        ),
        if (voiceOpen) _voiceOverlay(ref),
      ],
    );
  }

  Widget _voiceOverlay(WidgetRef ref) {
    return GestureDetector(
      onTap: () => ref.read(voiceOverlayOpenProvider.notifier).state = false,
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: Colors.black54,
        child: GestureDetector(
          onTap: () {},
          child: const Align(
            alignment: Alignment.bottomCenter,
            child: VoiceAssistantOverlay(),
          ),
        ),
      ),
    );
  }
}

/// Wrapper to show voice assistant in nav position 9
class VoiceScreenWrapper extends ConsumerWidget {
  const VoiceScreenWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB).withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF2563EB).withOpacity(0.3), width: 2),
              ),
              child: const Icon(Icons.mic_none_rounded, size: 36, color: Color(0xFF2563EB)),
            ),
            const SizedBox(height: 20),
            Text(
              'Voice Assistant',
              style: TextStyle(
                color: isDark ? const Color(0xFFF0F4F8) : const Color(0xFF0D1117),
                fontSize: 22,
                fontWeight: FontWeight.w700,
                fontFamily: 'SpaceGrotesk',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ask in English or ಕನ್ನಡ',
              style: TextStyle(
                color: isDark ? const Color(0xFF8A99AA) : const Color(0xFF4A5568),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: () => ref.read(voiceOverlayOpenProvider.notifier).state = true,
              icon: const Icon(Icons.mic_none_rounded),
              label: const Text('Open Voice Assistant'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
