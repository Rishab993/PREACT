import 'package:flutter/foundation.dart';

/// Central startup timeline used to measure operations from first frame onward.
class StartupTimer {
  StartupTimer._();

  static final Stopwatch _clock = Stopwatch();
  static bool _started = false;
  static final List<String> _timeline = [];

  static void start() {
    if (_started) return;
    _started = true;
    _clock.start();
    mark('StartupTimer started');
  }

  static void mark(String label) {
    if (!_started) start();
    final entry = '${_clock.elapsedMilliseconds}ms — $label';
    _timeline.add(entry);
    debugPrint('[StartupTimeline] $entry');
  }

  static Future<T> measure<T>(String label, Future<T> Function() action) async {
    if (!_started) start();
    final begin = _clock.elapsedMilliseconds;
    try {
      return await action();
    } finally {
      final duration = _clock.elapsedMilliseconds - begin;
      mark('$label (${duration}ms)');
    }
  }

  static List<String> get timeline => List.unmodifiable(_timeline);

  static void logSummary() {
    if (_timeline.isEmpty) return;
    debugPrint('[StartupTimeline] ── Summary (${_timeline.length} events) ──');
    for (final entry in _timeline) {
      debugPrint('[StartupTimeline]   $entry');
    }
  }
}
