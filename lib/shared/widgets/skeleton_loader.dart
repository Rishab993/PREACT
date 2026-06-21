import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';

/// Shimmer skeleton loader — uses AnimatedContainer for pulsing effect.
/// No external shimmer package required.
class SkeletonLoader extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;
  final EdgeInsetsGeometry? margin;

  const SkeletonLoader({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.borderRadius = 8,
    this.margin,
  });

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _anim = Tween(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        margin: widget.margin,
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.surfaceElevatedDark.withOpacity(_anim.value)
              : AppColors.borderLight.withOpacity(_anim.value + 0.2),
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
      ),
    );
  }
}

/// Card-shaped skeleton
class SkeletonCard extends StatelessWidget {
  final double height;
  const SkeletonCard({super.key, this.height = 100});

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).brightness == Brightness.dark
          ? AppColors.surfaceDark
          : AppColors.surfaceLight,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: Theme.of(context).brightness == Brightness.dark
            ? AppColors.borderDark
            : AppColors.borderLight,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const SkeletonLoader(width: 40, height: 40, borderRadius: 20),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonLoader(height: 14, width: MediaQuery.of(context).size.width * 0.4),
              const SizedBox(height: 6),
              const SkeletonLoader(height: 10),
            ],
          )),
        ]),
        const SizedBox(height: 12),
        const SkeletonLoader(height: 10),
        const SizedBox(height: 6),
        const SkeletonLoader(height: 10, width: 200),
      ],
    ),
  );
}

/// List of skeleton cards
class SkeletonList extends StatelessWidget {
  final int count;
  final double cardHeight;
  const SkeletonList({super.key, this.count = 4, this.cardHeight = 100});

  @override
  Widget build(BuildContext context) => Column(
    children: List.generate(count, (_) => SkeletonCard(height: cardHeight)),
  );
}

/// Chart skeleton
class SkeletonChart extends StatelessWidget {
  final double height;
  const SkeletonChart({super.key, this.height = 200});

  @override
  Widget build(BuildContext context) => SkeletonLoader(
    height: height,
    borderRadius: 16,
  );
}
