import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';

/// PREACT brand lockup reused across header, sidebar, login, and splash screens.
class BrandLogo extends StatefulWidget {
  /// Horizontal layout for app bar / drawer header.
  final bool compact;

  /// Centered full lockup for role selection.
  final bool hero;

  /// Startup splash: icon + title + tagline stacked vertically.
  final bool splash;

  /// Applies a subtle fade-in (splash / loading).
  final bool animate;

  /// Max width for the hero lockup image.
  final double heroWidth;

  /// Logo icon width on the splash screen (180-220px).
  final double splashLogoWidth;

  const BrandLogo({
    super.key,
    this.compact = false,
    this.hero = false,
    this.splash = false,
    this.animate = false,
    this.heroWidth = 300,
    this.splashLogoWidth = 240,
  });

  const BrandLogo.compact({super.key})
      : compact = true,
        hero = false,
        splash = false,
        animate = false,
        heroWidth = 300,
        splashLogoWidth = 240;

  const BrandLogo.hero({super.key, this.animate = false, this.heroWidth = 300})
      : compact = false,
        hero = true,
        splash = false,
        splashLogoWidth = 200;

  const BrandLogo.splash({super.key, this.animate = true, this.splashLogoWidth = 240})
      : compact = false,
        hero = false,
        splash = true,
        heroWidth = 300;

  static const String assetPath = 'assets/images/preact_logo.png';

  static const String title = 'PREACT';

  static const String tagline =
      'Proactive Resource Allocation & Event-Adaptive Command Tool';

  static const Color splashBackground = Color(0xFF020B1F);

  static const Color splashTaglineColor = Color(0xFF5B8DEF);

  @override
  State<BrandLogo> createState() => _BrandLogoState();
}

class _BrandLogoState extends State<BrandLogo> with SingleTickerProviderStateMixin {
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    if (widget.animate) {
      _fadeCtrl.forward();
    } else {
      _fadeCtrl.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant BrandLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !oldWidget.animate) {
      _fadeCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? AppColors.textPrimary : AppColors.textPrimaryDark;
    final taglineColor = isDark ? AppColors.textMuted : AppColors.textSecondaryDark;

    Widget content;
    if (widget.splash) {
      content = _buildSplash();
    } else if (widget.hero) {
      content = _buildHero();
    } else {
      content = _buildCompact(titleColor, taglineColor);
    }

    if (!widget.animate) return content;
    return FadeTransition(opacity: _fadeAnim, child: content);
  }

  Widget _buildSplash() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BrandIconMark(size: widget.splashLogoWidth),
        const SizedBox(height: 20),
        const Text(
          BrandLogo.title,
          style: TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: widget.splashLogoWidth + 80),
          child: const Text(
            BrandLogo.tagline,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: BrandLogo.splashTaglineColor,
              fontSize: 14,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHero() {
    return Image.asset(
      BrandLogo.assetPath,
      width: widget.heroWidth,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, size: 48),
    );
  }

  Widget _buildCompact(Color titleColor, Color taglineColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const _BrandIconMark(size: 64),
        const SizedBox(width: 14),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                BrandLogo.title,
                style: TextStyle(
                  color: titleColor,
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                BrandLogo.tagline,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: taglineColor,
                  fontSize: 14,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Icon portion of the PREACT logo (top of the lockup asset).
class _BrandIconMark extends StatelessWidget {
  final double size;

  const _BrandIconMark({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 0.56,
      child: ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: 0.56,
          child: Image.asset(
            BrandLogo.assetPath,
            width: size,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) => Icon(
              Icons.image_not_supported_outlined,
              size: size * 0.4,
              color: AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
