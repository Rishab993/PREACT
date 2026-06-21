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

class ForecastScreen extends ConsumerStatefulWidget {
  const ForecastScreen({super.key});

  @override
  ConsumerState<ForecastScreen> createState() => _ForecastScreenState();
}

class _ForecastScreenState extends ConsumerState<ForecastScreen>
    with SingleTickerProviderStateMixin {
  String _selectedZone = AppConstants.zones.first;
  bool _isLoading = false;
  List<ForecastModel> _forecasts = [];
  bool _fromCache = false;
  late AnimationController _entryCtrl;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 500),
    )..forward();
    _loadForecast();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadForecast() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiClient.instance.get(
        AppEndpoints.forecastByZone(_selectedZone),
      );
      _fromCache = ApiClient.instance.isFromCache(response);
      final data = response.data;
      if (data is List && data.isNotEmpty) {
        _forecasts = data.map((r) => ForecastModel.fromJson(r as Map<String, dynamic>)).toList();
      } else {
        _loadSeed();
      }
    } catch (_) {
      _loadSeed();
      _fromCache = true;
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _loadSeed() {
    _forecasts = ref.read(forecastsProvider(_selectedZone)).asData?.value ?? [];
    if (_forecasts.isEmpty) {
      // Generate seed data
      final now = DateTime.now();
      _forecasts = List.generate(72, (i) {
        final hour = now.add(Duration(hours: i));
        final h = hour.hour;
        double sev = 0.3;
        if (h >= 8 && h <= 10) sev = 0.72;
        if (h >= 17 && h <= 20) sev = 0.85;
        if (h >= 11 && h <= 16) sev = 0.45;
        return ForecastModel(
          id: 'seed-$i',
          zone: _selectedZone,
          forecastHour: hour,
          severity: sev,
          confidenceLower: (sev - 0.12).clamp(0, 1),
          confidenceUpper: (sev + 0.12).clamp(0, 1),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              const SizedBox(height: 20),
              _buildZoneSelector(),
              const SizedBox(height: 20),
              if (_fromCache)
                _buildCacheChip(),
              const SizedBox(height: 8),
              _isLoading
                  ? const SkeletonChart(height: 280)
                  : _buildForecastChart(),
              const SizedBox(height: 20),
              _buildZoneCardGrid(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Event Forecast', style: Theme.of(context).textTheme.displayLarge),
              Text(
                '72-hour severity prediction · Prophet + XGBoost',
                style: TextStyle(color: isDark ? AppColors.textSecondary : AppColors.textSecondaryDark, fontSize: 12),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: _loadForecast,
          icon: const Icon(Icons.refresh_outlined, color: Color(0xFF2563EB)),
          tooltip: 'Refresh forecast',
        ),
      ],
    );
  }

  Widget _buildZoneSelector() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Text('Zone:', style: TextStyle(color: isDark ? AppColors.textSecondary : AppColors.textSecondaryDark, fontSize: 13)),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceElevatedDark : AppColors.surfaceElevatedLight,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isDark ? AppColors.borderDark : AppColors.borderLight),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedZone,
              dropdownColor: isDark ? AppColors.surfaceElevatedDark : AppColors.surfaceElevatedLight,
              style: TextStyle(color: isDark ? AppColors.textPrimary : AppColors.textPrimaryDark, fontSize: 13),
              icon: Icon(Icons.keyboard_arrow_down, color: isDark ? AppColors.textSecondary : AppColors.textSecondaryDark, size: 18),
              items: AppConstants.zones.map((z) => DropdownMenuItem(
                value: z,
                child: Text(z),
              )).toList(),
              onChanged: (z) {
                if (z == null) return;
                setState(() => _selectedZone = z);
                _loadForecast();
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCacheChip() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: AppColors.amber.withOpacity(0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.amber.withOpacity(0.4)),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.history_outlined, color: AppColors.amber, size: 14),
        SizedBox(width: 4),
        Text('Using cached data', style: TextStyle(color: AppColors.amber, fontSize: 11, fontWeight: FontWeight.w500)),
      ],
    ),
  );

  Widget _buildForecastChart() {
    if (_forecasts.isEmpty) return const SkeletonChart(height: 280);

    // Show next 24 hours
    final next24 = _forecasts.take(24).toList();

    final spots = next24.asMap().entries.map((e) =>
      FlSpot(e.key.toDouble(), e.value.severity)).toList();
    final upperSpots = next24.asMap().entries.map((e) =>
      FlSpot(e.key.toDouble(), (e.value.confidenceUpper ?? e.value.severity + 0.1).clamp(0, 1))).toList();
    final lowerSpots = next24.asMap().entries.map((e) =>
      FlSpot(e.key.toDouble(), (e.value.confidenceLower ?? e.value.severity - 0.1).clamp(0, 1))).toList();

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '72-hour Forecast — $_selectedZone',
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              _legendDot(const Color(0xFF2563EB), 'Severity'),
              const SizedBox(width: 12),
              _legendDot(const Color(0xFF2563EB).withOpacity(0.3), 'Confidence interval'),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: AppColors.borderDark,
                    strokeWidth: 0.5,
                  ),
                ),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 4,
                      getTitlesWidget: (val, _) {
                        if (val.toInt() >= next24.length) return const SizedBox();
                        final dt = next24[val.toInt()].forecastHour;
                        return Text(
                          '${dt.hour}:00',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 9),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 0.25,
                      getTitlesWidget: (val, _) => Text(
                        '${(val * 100).toInt()}%',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 9),
                      ),
                      reservedSize: 32,
                    ),
                  ),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                minY: 0, maxY: 1,
                lineBarsData: [
                  // Confidence upper bound (dashed)
                  LineChartBarData(
                    spots: upperSpots,
                    isCurved: true,
                    color: const Color(0xFF2563EB).withOpacity(0.3),
                    barWidth: 1,
                    dotData: const FlDotData(show: false),
                    dashArray: [4, 4],
                    belowBarData: BarAreaData(
                      show: true,
                      color: const Color(0xFF2563EB).withOpacity(0.06),
                      spotsLine: BarAreaSpotsLine(show: false),
                    ),
                  ),
                  // Confidence lower bound (dashed)
                  LineChartBarData(
                    spots: lowerSpots,
                    isCurved: true,
                    color: const Color(0xFF2563EB).withOpacity(0.3),
                    barWidth: 1,
                    dotData: const FlDotData(show: false),
                    dashArray: [4, 4],
                  ),
                  // Main severity line
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    gradient: LinearGradient(colors: [AppColors.green, AppColors.amber, AppColors.red]),
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                    shadow: Shadow(color: const Color(0xFF2563EB).withOpacity(0.2), blurRadius: 6),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFF2563EB).withOpacity(0.12),
                          const Color(0xFF2563EB).withOpacity(0.0),
                        ],
                      ),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (_) => Theme.of(context).brightness == Brightness.dark
                          ? AppColors.surfaceElevatedDark
                          : AppColors.surfaceElevatedLight,
                      getTooltipItems: (spots) => spots.map((s) => LineTooltipItem(
                        '${(s.y * 100).toStringAsFixed(0)}%',
                        const TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.w700),
                      )).toList(),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Shaded region = 80% confidence interval · Gradient line = severity tier',
            style: TextStyle(color: AppColors.textMuted, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 12, height: 3, color: color),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
    ],
  );

  Widget _buildZoneCardGrid() {
    final zones = AppConstants.zones;
    final severities = [0.82, 0.65, 0.48, 0.35, 0.55, 0.72, 0.40, 0.60, 0.45, 0.30];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'All Zones',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12, letterSpacing: 0.5),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            // Responsive columns: 1 on mobile, 2 on tablet/narrow, 3 on desktop
            final crossCount = constraints.maxWidth < 480
                ? 1
                : (constraints.maxWidth > 750 ? 3 : 2);
            // Each card: gauge (60) + padding (10) + text column (~48)
            // card width ≈ (maxWidth - spacing*(count-1)) / count
            final cardW = (constraints.maxWidth - (12.0 * (crossCount - 1))) / crossCount;
            // Height needed: gauge=60, horizontal padding, text ~48, vertical padding=24
            const cardH = 88.0;
            final ratio = cardW / cardH;

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossCount,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: ratio.clamp(1.2, 3.6),
              ),
              itemCount: zones.length,
              itemBuilder: (_, i) {
                final sev = severities[i % severities.length];
                final color = AppColors.fromSeverity(sev);
                final gaugeSize = cardW < 180 ? 48.0 : 56.0;
                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedZone = zones[i]);
                    _loadForecast();
                  },
                  child: GlassCard(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    borderColor: _selectedZone == zones[i] ? color : null,
                    child: Row(
                      children: [
                        SeverityGauge(value: sev, size: gaugeSize, strokeWidth: 5),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                zones[i],
                                style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  sev >= 0.7 ? 'HIGH' : sev >= 0.4 ? 'MED' : 'LOW',
                                  style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}
