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
import '../../shared/widgets/severity_gauge.dart';

class ShadowScreen extends ConsumerStatefulWidget {
  const ShadowScreen({super.key});

  @override
  ConsumerState<ShadowScreen> createState() => _ShadowScreenState();
}

class _ShadowScreenState extends ConsumerState<ShadowScreen>
    with SingleTickerProviderStateMixin {
  String? _selectedEventId;
  Map<String, dynamic>? _shadowData;
  bool _isLoading = false;
  late AnimationController _fadeCtrl;
  List<DebriefModel> _similarEvents = [];

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500))..forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _loadShadowSeed() {
    _shadowData = {
      'event_name': 'IPL RCB vs CSK',
      'preact_congestion': 54.0,
      'actual_congestion': 87.0,
      'congestion_avoided': 33.0,
      'regret_score': 0.38,
      'preact_deployments': [
        {'junction': 'Silk Board Junction', 'officers': 4, 'priority': 'high'},
        {'junction': 'Mekhri Circle', 'officers': 3, 'priority': 'high'},
        {'junction': 'Hebbal Flyover Junction', 'officers': 2, 'priority': 'medium'},
        {'junction': 'Koramangala Water Tank Junction', 'officers': 3, 'priority': 'medium'},
      ],
      'actual_deployments': [
        {'junction': 'Silk Board Junction', 'officers': 2, 'priority': 'medium'},
        {'junction': 'Mekhri Circle', 'officers': 2, 'priority': 'low'},
        {'junction': 'Hebbal Flyover Junction', 'officers': 1, 'priority': 'low'},
        {'junction': 'Koramangala Water Tank Junction', 'officers': 1, 'priority': 'low'},
      ],
    };
    _similarEvents = _seedSimilar();
  }

  List<DebriefModel> _seedSimilar() => [
    DebriefModel(id: 's1', eventName: 'IPL RCB vs PBKS · Mar 12', expectedAttendance: 32000, regretScore: 0.12, topIntervention: 'Gate 2 needed 2 more officers'),
    DebriefModel(id: 's2', eventName: 'IPL RCB vs MI · Jan 5',   expectedAttendance: 38000, regretScore: 0.61, topIntervention: 'No diversion planned'),
    DebriefModel(id: 's3', eventName: 'IPL Finals · Apr 20',      expectedAttendance: 45000, regretScore: 0.28, topIntervention: 'Diversion Route B saved 28%'),
  ];

  Future<void> _loadShadow(String eventId) async {
    setState(() => _isLoading = true);
    try {
      final resp = await ApiClient.instance.get(AppEndpoints.shadow(eventId));
      if (resp.data is Map) {
        setState(() => _shadowData = Map<String, dynamic>.from(resp.data));
      }
      // Also load similar
      final simResp = await ApiClient.instance.get(AppEndpoints.memorySimilar(eventId));
      if (simResp.data is List) {
        setState(() => _similarEvents = (simResp.data as List)
            .map((r) => DebriefModel.fromJson(r as Map<String, dynamic>))
            .toList());
      }
    } catch (e) {
      debugPrint('[Shadow] Failed to load backend data: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
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
              _buildEventPicker(),
              const SizedBox(height: 20),
              if (_isLoading)
                const SkeletonCard(height: 400)
              else if (_shadowData != null) ...[
                _buildHeroMetrics(),
                const SizedBox(height: 20),
                _buildBarChart(),
                const SizedBox(height: 20),
                _buildSimilarEvents(),
              ] else
                const Text(
                  'Select an event to load shadow analysis.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Shadow Analysis', style: Theme.of(context).textTheme.displayLarge),
      const Text(
        'PREACT recommended vs actual deployment',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
    ],
  );

  Widget _buildEventPicker() {
    return ref.watch(eventsProvider).when(
      loading: () => const SkeletonLoader(height: 52),
      error: (_, __) => const SizedBox(),
      data: (events) => Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _selectedEventId,
              decoration: InputDecoration(
                labelText: 'Select completed event',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              dropdownColor: AppColors.surfaceElevatedDark,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              items: events.map((e) => DropdownMenuItem(
                value: e.id,
                child: Text('${e.name} · ${e.locationName ?? ""}', overflow: TextOverflow.ellipsis),
              )).toList(),
              onChanged: (id) {
                setState(() => _selectedEventId = id);
                if (id != null) _loadShadow(id);
              },
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: () {
              if (_selectedEventId != null) _loadShadow(_selectedEventId!);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: AppColors.backgroundDark,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            ),
            child: const Text('Analyse'),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroMetrics() {
    final shadow = _shadowData!;
    final regret = (shadow['regret_score'] as num?)?.toDouble() ?? 0.38;
    final avoided = (shadow['congestion_avoided'] as num?)?.toDouble() ?? 33.0;
    final preact = (shadow['preact_congestion'] as num?)?.toDouble() ?? 54.0;
    final actual = (shadow['actual_congestion'] as num?)?.toDouble() ?? 87.0;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: GlassCard(
                child: Column(
                  children: [
                    const Text('PREACT Estimate', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    const SizedBox(height: 8),
                    Text(
                      '${preact.toStringAsFixed(0)} min',
                      style: const TextStyle(color: const Color(0xFF2563EB), fontSize: 32, fontWeight: FontWeight.w700, fontFamily: 'SpaceGrotesk'),
                    ),
                    const Text('congestion', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GlassCard(
                child: Column(
                  children: [
                    const Text('Actual', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    const SizedBox(height: 8),
                    Text(
                      '${actual.toStringAsFixed(0)} min',
                      style: const TextStyle(color: AppColors.red, fontSize: 32, fontWeight: FontWeight.w700, fontFamily: 'SpaceGrotesk'),
                    ),
                    const Text('congestion', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GlassCard(
          borderColor: avoided > 0 ? AppColors.green : AppColors.red,
          child: Row(
            children: [
              SeverityGauge(value: regret, size: 90, label: 'Regret', strokeWidth: 8),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Congestion Avoided', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(
                      '${avoided.abs().toStringAsFixed(0)} minutes',
                      style: TextStyle(
                        color: avoided > 0 ? AppColors.green : AppColors.red,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'SpaceGrotesk',
                      ),
                    ),
                    Text(
                      avoided > 0
                          ? 'could have been saved by following PREACT\'s plan'
                          : 'PREACT plan underestimated demand',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.amber.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Regret Score: ${(regret * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(color: AppColors.amber, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBarChart() {
    final shadow = _shadowData!;
    final preactDeps = List<Map<String, dynamic>>.from(shadow['preact_deployments'] ?? []);
    final actualDeps = List<Map<String, dynamic>>.from(shadow['actual_deployments'] ?? []);

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text('Officer Deployment Comparison', style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
              Spacer(),
              _Legend(color: const Color(0xFF2563EB), label: 'PREACT'),
              SizedBox(width: 12),
              _Legend(color: AppColors.amber, label: 'Actual'),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                groupsSpace: 16,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.borderDark, strokeWidth: 0.5),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      getTitlesWidget: (val, _) => Text('${val.toInt()}', style: const TextStyle(color: AppColors.textMuted, fontSize: 9)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (val, _) {
                        final i = val.toInt();
                        if (i >= preactDeps.length) return const SizedBox();
                        final name = (preactDeps[i]['junction'] as String).split(' ').first;
                        return Text(name, style: const TextStyle(color: AppColors.textMuted, fontSize: 8));
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                barGroups: List.generate(preactDeps.length, (i) {
                  final preactOff = (preactDeps[i]['officers'] as num?)?.toDouble() ?? 0;
                  final actualOff = i < actualDeps.length
                      ? (actualDeps[i]['officers'] as num?)?.toDouble() ?? 0
                      : 0.0;
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(toY: preactOff, color: const Color(0xFF2563EB), width: 12, borderRadius: BorderRadius.circular(4)),
                      BarChartRodData(toY: actualOff, color: AppColors.amber, width: 12, borderRadius: BorderRadius.circular(4)),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimilarEvents() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.history_edu_outlined, color: AppColors.purple, size: 16),
            SizedBox(width: 6),
            Text('Similar Past Events', style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 10),
        ..._similarEvents.map((d) => GlassCard(
          margin: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.eventName ?? 'Unknown', style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(d.attendanceDisplay, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    if (d.topIntervention != null)
                      Text('✓ ${d.topIntervention}', style: const TextStyle(color: AppColors.green, fontSize: 11)),
                  ],
                ),
              ),
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.fromSeverity(d.regretScore ?? 0).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      d.regretLabel,
                      style: TextStyle(color: AppColors.fromSeverity(d.regretScore ?? 0), fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text('regret', style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
                ],
              ),
            ],
          ),
        )),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
    ],
  );
}
