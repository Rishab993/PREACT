import 'package:flutter/material.dart';
import '../../shared/widgets/brand_logo.dart';

/// Active Flutter startup splash — rendered by [PreactBootstrap] until critical init completes.
class StartupSplashScreen extends StatelessWidget {
  const StartupSplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: BrandLogo.splashBackground,
      body: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: BrandLogo.splash(animate: true, splashLogoWidth: 240),
        ),
      ),
    );
  }
}
