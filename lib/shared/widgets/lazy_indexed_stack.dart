import 'package:flutter/material.dart';

/// [IndexedStack] that only builds a child the first time its tab becomes active.
///
/// Preserves state for visited tabs while avoiding startup work for every screen.
class LazyIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget Function()> builders;

  const LazyIndexedStack({
    super.key,
    required this.index,
    required this.builders,
  });

  @override
  State<LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<LazyIndexedStack> {
  late Set<int> _activated;

  @override
  void initState() {
    super.initState();
    _activated = {widget.index.clamp(0, widget.builders.length - 1)};
  }

  @override
  void didUpdateWidget(covariant LazyIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    final clamped = widget.index.clamp(0, widget.builders.length - 1);
    if (!_activated.contains(clamped)) {
      _activated = {..._activated, clamped};
    }
  }

  @override
  Widget build(BuildContext context) {
    final clamped = widget.index.clamp(0, widget.builders.length - 1);
    return IndexedStack(
      index: clamped,
      sizing: StackFit.expand,
      children: List.generate(widget.builders.length, (i) {
        if (!_activated.contains(i)) {
          return const SizedBox.shrink();
        }
        return widget.builders[i]();
      }),
    );
  }
}
