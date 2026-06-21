import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/theme/colors.dart';
import '../../core/api/endpoints.dart';
import '../../core/api/api_client.dart';
import '../../providers/data_providers.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/skeleton_loader.dart';

class SimulatorScreen extends ConsumerStatefulWidget {
  const SimulatorScreen({super.key});

  @override
  ConsumerState<SimulatorScreen> createState() => _SimulatorScreenState();
}

class _SimulatorScreenState extends ConsumerState<SimulatorScreen>
    with SingleTickerProviderStateMixin {
  String? _selectedEventId;
  Timer? _debounce;
  Map<String, int> _officerCounts = {};
  Map<String, bool> _barricades = {};
  Map<String, dynamic>? _simResult;
  bool _isSimulating = false;
  List<SimulationModel> _savedScenarios = [];
  late AnimationController _fadeCtrl;

  // Junction list for controls
  final _junctions = AppConstants.junctions.take(6).toList();

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400))..forward();
    for (final j in _junctions) {
      _officerCounts[j['name'] as String] = 3;
      _barricades[j['name'] as String] = false;
    }
    _runSeedSimulation();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _runSeedSimulation() {
    _simResult = {
      'zones': AppConstants.zones.map((z) => {
        'zone': z,
        'severity_curve': List.generate(24, (i) {
          final h = i;
          double s = 0.3;
          if (h >= 17 && h <= 20) s = 0.75;
          if (h >= 8 && h <= 10) s = 0.65;
          return s + (0.05 * ((z.hashCode + i) % 3 - 1));
        }),
        'peak_hour': 18,
        'risk_tier': z.contains('Central') ? 'HIGH' : 'MEDIUM',
      }).toList(),
      'summary': {
        'total_congestion_min': 47.0,
        'vs_optimal_delta': 12.0,
        'recommendation': 'Add 2 officers to Silk Board Junction during 17:00–20:00 window',
      },
    };
  }

  void _onSliderChanged(String junction, double value) {
    setState(() => _officerCounts[junction] = value.toInt());
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: AppConstants.simulatorDebounceMs),
      _callSimulate,
    );
  }

  Future<void> _callSimulate() async {
    if (_selectedEventId == null) return;
    setState(() => _isSimulating = true);
    try {
      final scenario = _junctions.map((j) => {
        'junction': j['name'],
        'officer_count': _officerCounts[j['name']],
        'barricade_active': _barricades[j['name']],
        'start_time': '17:00',
      }).toList();

      final response = await ApiClient.instance.post(AppEndpoints.simulate, data: {
        'event_id': _selectedEventId,
        'scenario': scenario,
      });
      if (response.data is Map) {
        setState(() => _simResult = Map<String, dynamic>.from(response.data));
      }
    } catch (_) {
      _runSeedSimulation();
    }
    if (mounted) setState(() => _isSimulating = false);
  }

  Future<void> _saveScenario() async {
    if (_selectedEventId == null || _simResult == null) return;
    try {
      await ApiClient.instance.post(AppEndpoints.simulate, data: {
        'event_id': _selectedEventId,
        'label': 'Scenario ${_savedScenarios.length + 1}',
        'save': true,
        'scenario': _junctions.map((j) => {
          'junction': j['name'],
          'officer_count': _officerCounts[j['name']],
          'barricade_active': _barricades[j['name']],
        }).toList(),
      });
    } catch (_) {}
    final saved = SimulationModel(
      id: 'local-${DateTime.now().millisecondsSinceEpoch}',
      eventId: _selectedEventId,
      label: 'Scenario ${_savedScenarios.length + 1}',
      totalCongestionMin: (_simResult!['summary']?['total_congestion_min'] as num?)?.toDouble(),
      vsOptimalDeltaMin: (_simResult!['summary']?['vs_optimal_delta'] as num?)?.toDouble(),
    );
    setState(() => _savedScenarios.add(saved));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${saved.label} saved'), backgroundColor: AppColors.green),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 1000;

    return FadeTransition(
      opacity: CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              const SizedBox(height: 16),
              _buildEventSelector(),
              const SizedBox(height: 20),
              isWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildSliderControls()),
                        const SizedBox(width: 16),
                        Expanded(child: _buildResultsPanel()),
                      ],
                    )
                  : Column(children: [
                      _buildSliderControls(),
                      const SizedBox(height: 16),
                      _buildResultsPanel(),
                    ]),
              if (_savedScenarios.isNotEmpty) ...[
                const SizedBox(height: 20),
                _buildSavedScenarios(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Scenario Simulator', style: Theme.of(context).textTheme.displayLarge),
            const Text('Real-time XGBoost inference — debounced 400ms', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
      ),
      Row(
        children: [
          OutlinedButton.icon(
            onPressed: _saveScenario,
            icon: const Icon(Icons.save_outlined, size: 14),
            label: const Text('Save Scenario', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    ],
  );

  Widget _buildEventSelector() => ref.watch(eventsProvider).when(
    loading: () => const SkeletonLoader(height: 52),
    error: (_, __) => const SizedBox(),
    data: (events) => DropdownButtonFormField<String>(
      value: _selectedEventId,
      decoration: InputDecoration(
        labelText: 'Select upcoming event',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dropdownColor: AppColors.surfaceElevatedDark,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
      items: events.map((e) => DropdownMenuItem(
        value: e.id,
        child: Text('${e.name} · ${e.locationName ?? e.status ?? ""}', overflow: TextOverflow.ellipsis),
      )).toList(),
      onChanged: (id) { setState(() => _selectedEventId = id); _callSimulate(); },
    ),
  );

  Widget _buildSliderControls() => GlassCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Junction Controls', style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        ..._junctions.map((j) {
          final name = j['name'] as String;
          final count = _officerCounts[name] ?? 3;
          final barricade = _barricades[name] ?? false;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Text(name.split(' ').first + (name.split(' ').length > 1 ? ' ${name.split(' ')[1]}' : ''),
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              Row(
                children: [
                  const Icon(Icons.people_alt_outlined, size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  const Text('Officers:', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                  Expanded(
                    child: Slider(
                      value: count.toDouble(),
                      min: 0, max: 10,
                      divisions: 10,
                      label: '$count',
                      onChanged: (v) => _onSliderChanged(name, v),
                    ),
                  ),
                  Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Center(child: Text('$count', style: const TextStyle(color: const Color(0xFF2563EB), fontSize: 12, fontWeight: FontWeight.w700))),
                  ),
                ],
              ),
              Row(
                children: [
                  const Icon(Icons.fence_outlined, size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  const Text('Barricade:', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                  const SizedBox(width: 8),
                  Switch(
                    value: barricade,
                    onChanged: (v) {
                      setState(() => _barricades[name] = v);
                      _debounce?.cancel();
                      _debounce = Timer(const Duration(milliseconds: AppConstants.simulatorDebounceMs), _callSimulate);
                    },
                  ),
                  Text(barricade ? 'ON' : 'OFF', style: TextStyle(color: barricade ? AppColors.green : AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
                ],
              ),
              const Divider(color: AppColors.borderDark, height: 1),
            ],
          );
        }),
      ],
    ),
  );

  Widget _buildResultsPanel() {
    if (_simResult == null) return const SkeletonChart(height: 300);
    final summary = _simResult!['summary'] as Map? ?? {};
    final zones = (_simResult!['zones'] as List? ?? []);

    final totalMin = (summary['total_congestion_min'] as num?)?.toDouble() ?? 47;
    final delta = (summary['vs_optimal_delta'] as num?)?.toDouble() ?? 12;
    final rec = summary['recommendation']?.toString() ?? '';

    return Column(
      children: [
        // Summary metrics
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Predicted Outcome', style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  if (_isSimulating)
                    const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: const Color(0xFF2563EB))),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: Column(
                    children: [
                      Text('${totalMin.toStringAsFixed(0)}', style: const TextStyle(color: AppColors.textPrimary, fontSize: 36, fontWeight: FontWeight.w700, fontFamily: 'SpaceGrotesk')),
                      const Text('min congestion', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    ],
                  )),
                  Container(width: 1, height: 50, color: AppColors.borderDark),
                  Expanded(child: Column(
                    children: [
                      Text(
                        '+${delta.toStringAsFixed(0)}',
                        style: TextStyle(
                          color: delta > 0 ? AppColors.red : AppColors.green,
                          fontSize: 36, fontWeight: FontWeight.w700, fontFamily: 'SpaceGrotesk',
                        ),
                      ),
                      Text('vs optimal', style: TextStyle(color: delta > 0 ? AppColors.red : AppColors.green, fontSize: 11)),
                    ],
                  )),
                ],
              ),
              if (rec.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF2563EB).withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lightbulb_outline, color: const Color(0xFF2563EB), size: 14),
                      const SizedBox(width: 6),
                      Expanded(child: Text(rec, style: const TextStyle(color: const Color(0xFF2563EB), fontSize: 11))),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Severity chart
        if (zones.isNotEmpty) GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Severity Curves', style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              SizedBox(
                height: 180,
                child: LineChart(
                  LineChartData(
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.borderDark, strokeWidth: 0.5),
                    ),
                    borderData: FlBorderData(show: false),
                    minY: 0, maxY: 1,
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 28,
                          getTitlesWidget: (v, _) => Text('${(v * 100).toInt()}%', style: const TextStyle(color: AppColors.textMuted, fontSize: 8)),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: 4,
                          getTitlesWidget: (v, _) => Text('${v.toInt()}:00', style: const TextStyle(color: AppColors.textMuted, fontSize: 8)),
                        ),
                      ),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    lineBarsData: zones.take(5).toList().asMap().entries.map((e) {
                      final z = e.value as Map;
                      final curve = List<double>.from(z['severity_curve'] ?? []);
                      final color = AppColors.forZone(e.key);
                      return LineChartBarData(
                        spots: curve.asMap().entries.map((p) => FlSpot(p.key.toDouble(), p.value.clamp(0, 1))).toList(),
                        isCurved: true,
                        color: color,
                        barWidth: 2,
                        dotData: const FlDotData(show: false),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSavedScenarios() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Saved Scenarios', style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          ..._savedScenarios.map((s) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.forZone(_savedScenarios.indexOf(s)),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(s.label ?? 'Scenario', style: const TextStyle(color: AppColors.textPrimary, fontSize: 13))),
                Text('${s.totalCongestionMin?.toStringAsFixed(0) ?? "—"} min', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(width: 8),
                Text(
                  '+${s.vsOptimalDeltaMin?.toStringAsFixed(0) ?? "—"}',
                  style: TextStyle(
                    color: (s.vsOptimalDeltaMin ?? 0) > 0 ? AppColors.red : AppColors.green,
                    fontSize: 12, fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
}
