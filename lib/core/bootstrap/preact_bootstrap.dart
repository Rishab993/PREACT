import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../config/app_config.dart';
import '../api/api_client.dart';
import '../../preact_app.dart';
import 'startup_splash_screen.dart';
import 'startup_timer.dart';

/// Shows the splash until **critical** initialization completes, then renders the app.
///
/// Critical: `.env`, config validation, ApiClient.
/// Non-critical (Supabase, data providers): deferred to [StartupCoordinator].
class PreactBootstrap extends StatefulWidget {
  const PreactBootstrap({super.key});

  @override
  State<PreactBootstrap> createState() => _PreactBootstrapState();
}

class _PreactBootstrapState extends State<PreactBootstrap> {
  bool _ready = false;
  bool _failed = false;
  final List<String> _diagnostics = [];
  Object? _startupError;
  StackTrace? _startupStack;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeCriticalPath());
  }

  Future<void> _initializeCriticalPath() async {
    StartupTimer.start();
    StartupTimer.mark('First Flutter frame rendered');

    try {
      StartupTimer.mark('Loading .env');
      await dotenv.load(fileName: '.env');
      StartupTimer.mark('.env loaded');

      StartupTimer.mark('Validating configuration');
      AppConfig.validate();
      StartupTimer.mark('Configuration validated');

      StartupTimer.mark('Initializing ApiClient');
      initApiClient();
      StartupTimer.mark('ApiClient ready');

      StartupTimer.mark('Critical bootstrap complete — dismissing splash');
      _diagnostics.addAll(StartupTimer.timeline);
      if (mounted) setState(() => _ready = true);
    } catch (e, stack) {
      StartupTimer.mark('Critical bootstrap failed: $e');
      if (mounted) {
        setState(() {
          _failed = true;
          _startupError = e;
          _startupStack = stack;
          _diagnostics.addAll(StartupTimer.timeline);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(),
        home: _StartupErrorScreen(
          diagnostics: _diagnostics,
          error: _startupError,
          stack: _startupStack,
        ),
      );
    }

    if (!_ready) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: StartupSplashScreen(),
      );
    }

    return const ProviderScope(child: PreactApp());
  }
}

class _StartupErrorScreen extends StatelessWidget {
  final List<String> diagnostics;
  final Object? error;
  final StackTrace? stack;

  const _StartupErrorScreen({
    required this.diagnostics,
    required this.error,
    required this.stack,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          padding: const EdgeInsets.all(24),
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFF3B3B), width: 1.5),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.error_outline, color: Color(0xFFFF3B3B), size: 36),
                    SizedBox(width: 12),
                    Text(
                      'PREACT Startup Error',
                      style: TextStyle(
                        color: Color(0xFFF0F4F8),
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1117),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    diagnostics.join('\n'),
                    style: const TextStyle(
                      color: Color(0xFF43D97D),
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text('$error', style: const TextStyle(color: Color(0xFFFF3B3B), fontSize: 13)),
                if (stack != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '$stack',
                    style: const TextStyle(
                      color: Color(0xFF8A99AA),
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
