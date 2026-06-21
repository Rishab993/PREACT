import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/supabase_service.dart';
import '../bootstrap/startup_timer.dart';
import '../../providers/data_providers.dart';

/// Runs non-critical initialization after the first app screen is visible.
class StartupCoordinator extends ConsumerStatefulWidget {
  final Widget child;

  const StartupCoordinator({super.key, required this.child});

  @override
  ConsumerState<StartupCoordinator> createState() => _StartupCoordinatorState();
}

class _StartupCoordinatorState extends ConsumerState<StartupCoordinator> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      StartupTimer.mark('App shell first frame');
      unawaited(_initializeBackgroundServices());
    });
  }

  Future<void> _initializeBackgroundServices() async {
    if (SupabaseService.isInitialized) {
      StartupTimer.mark('Supabase already initialized');
      return;
    }

    await StartupTimer.measure('Supabase initialization (background)', () async {
      await SupabaseService.initialize();
      return SupabaseService.isInitialized;
    });

    if (!mounted) return;

    StartupTimer.mark('Refreshing KPI after Supabase');
    ref.invalidate(kpiSecondaryProvider);
    ref.invalidate(kpiProvider);

    StartupTimer.mark('Background startup complete');
    StartupTimer.logSummary();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
