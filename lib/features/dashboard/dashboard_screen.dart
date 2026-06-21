import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/theme/colors.dart';
import '../../core/api/endpoints.dart';
import '../../core/config/app_config.dart';
import '../../core/bootstrap/startup_timer.dart';
import '../../providers/data_providers.dart';
import '../../providers/app_providers.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/alert_card.dart';
import '../../shared/widgets/kpi_tile.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/skeleton_loader.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with TickerProviderStateMixin {
  late PageController _carouselCtrl;
  int _carouselPage = 0;
  late AnimationController _entryCtrl;
  late Animation<double> _fadeAnim;
  Timer? _carouselTimer;
  bool _mapReady = false;

  final _mapCtrl = MapController();

  @override
  void initState() {
    super.initState();
    StartupTimer.mark('DashboardScreen mounted');
    _carouselCtrl = PageController();
    _entryCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      StartupTimer.mark('Dashboard first frame rendered');
      if (mounted) setState(() => _mapReady = true);
      // Defer heavy KPI fetches so alerts render first.
      ref.read(kpiSecondaryProvider.future);
    });
    _startCarousel();
  }

  void _startCarousel() {
    _carouselTimer?.cancel();
    _carouselTimer = Timer.periodic(
      const Duration(seconds: AppConstants.carouselIntervalSeconds),
      (_) {
        if (!mounted || !_carouselCtrl.hasClients) return;
        const count = 5;
        final next = (_carouselPage + 1) % count;
        _carouselCtrl.animateToPage(
          next,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
        if (mounted) setState(() => _carouselPage = next);
      },
    );
  }

  @override
  void dispose() {
    _carouselTimer?.cancel();
    _carouselCtrl.dispose();
    _entryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 1100;

    return FadeTransition(
      opacity: _fadeAnim,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: _buildVoiceFab(),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context),
                const SizedBox(height: 16),
                _buildInsightCarousel(),
                const SizedBox(height: 20),
                isWide ? _buildWideLayout() : _buildNarrowLayout(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final now = DateTime.now();
    final days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final dateStr = '${days[now.weekday-1]}, ${now.day} ${months[now.month-1]} · ${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}';

    final role = ref.watch(roleProvider);
    final title = role == AppRole.citizen ? 'Traffic Portal Dashboard' : 'Command Dashboard';

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  color: isDark ? AppColors.textPrimary : AppColors.textPrimaryDark,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.circle, color: AppColors.green, size: 8),
                  const SizedBox(width: 6),
                  Text(
                    'LIVE · $dateStr',
                    style: TextStyle(color: isDark ? AppColors.textSecondary : AppColors.textSecondaryDark, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInsightCarousel() {
    final insights = [
      _InsightCard(
        icon: Icons.insights,
        color: const Color(0xFF2563EB),
        title: 'IPL Match Tonight',
        body: 'Expect 35K attendees at Chinnaswamy. Pre-position 8 officers by 17:30.',
      ),
      _InsightCard(
        icon: Icons.warning_amber_outlined,
        color: AppColors.amber,
        title: 'Silk Board Alert',
        body: 'Accident clearance in progress. Estimated 45 min delay on elevated corridor.',
      ),
      _InsightCard(
        icon: Icons.psychology_outlined,
        color: AppColors.purple,
        title: 'Similar Past Event',
        body: 'Rajyotsava 2024: Diversion Route B reduced delays by 28%. Consider applying.',
      ),
      _InsightCard(
        icon: Icons.trending_up,
        color: AppColors.green,
        title: 'Forecast Accuracy',
        body: 'PREACT predicted yesterday\'s congestion within 8%. Model confidence: HIGH.',
      ),
      _InsightCard(
        icon: Icons.volunteer_activism,
        color: AppColors.amber,
        title: '3 New Volunteers',
        body: '3 citizen volunteers pending approval for this weekend. Review in Volunteers tab.',
      ),
    ];

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('AI Insights', style: TextStyle(color: isDark ? AppColors.textSecondary : AppColors.textSecondaryDark, fontSize: 12, letterSpacing: 0.5)),
        const SizedBox(height: 8),
        SizedBox(
          height: 90,
          child: PageView.builder(
            controller: _carouselCtrl,
            onPageChanged: (p) => setState(() => _carouselPage = p),
            itemCount: insights.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GlassCard(
                onTap: () {},
                child: Row(
                  children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: insights[i].color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(insights[i].icon, color: insights[i].color, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            insights[i].title,
                            style: TextStyle(
                              color: isDark ? AppColors.textPrimary : AppColors.textPrimaryDark,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            insights[i].body,
                            style: TextStyle(color: isDark ? AppColors.textSecondary : AppColors.textSecondaryDark, fontSize: 12),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 18),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(insights.length, (i) => AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == _carouselPage ? 16 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == _carouselPage ? const Color(0xFF2563EB) : AppColors.borderDark,
              borderRadius: BorderRadius.circular(3),
            ),
          )),
        ),
      ],
    );
  }

  Widget _buildWideLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left column — KPI tiles
        Flexible(
          flex: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: _buildKpiColumn(),
          ),
        ),
        const SizedBox(width: 16),
        // Center — Map
        Expanded(
          flex: 3,
          child: _buildDeferredMapCard(),
        ),
        const SizedBox(width: 16),
        // Right — sparklines + alert feed
        Flexible(
          flex: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Column(
              children: [
                _buildSparklines(),
                const SizedBox(height: 16),
                _buildAlertFeed(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNarrowLayout() {
    return Column(
      children: [
        _buildKpiRow(),
        const SizedBox(height: 16),
        _buildDeferredMapCard(),
        const SizedBox(height: 16),
        _buildAlertFeed(),
      ],
    );
  }

  Widget _buildKpiColumn() {
    final role = ref.read(roleProvider);
    final isCitizen = role == AppRole.citizen;
    return ref.watch(kpiProvider).when(
      loading: () => const SkeletonList(count: 4, cardHeight: 110),
      error: (_, __) => const SkeletonList(count: 4, cardHeight: 110),
      data: (kpi) {
        if (isCitizen) {
          return Column(
            children: [
              KpiTile(
                label: 'Active Events',
                value: '${kpi['active_events'] ?? 0}',
                icon: Icons.event_outlined,
                color: const Color(0xFF2563EB),
                subtitle: 'Causing traffic shifts',
              ),
              const SizedBox(height: 12),
              KpiTile(
                label: 'Active Alerts',
                value: '${kpi['active_alerts'] ?? 0}',
                icon: Icons.notifications_active_outlined,
                color: AppColors.red,
                subtitle: 'City-wide warning',
              ),
              const SizedBox(height: 12),
              KpiTile(
                label: 'Pending Volunteers',
                value: '${kpi['volunteers_pending'] ?? 0}',
                icon: Icons.volunteer_activism_outlined,
                color: AppColors.green,
                subtitle: 'Awaiting approval',
              ),
            ],
          );
        }
        return Column(
          children: [
            KpiTile(
              label: 'Active Events',
              value: '${kpi['active_events'] ?? 0}',
              icon: Icons.event_outlined,
              color: const Color(0xFF2563EB),
              subtitle: 'Next 24 hours',
            ),
            const SizedBox(height: 12),
            KpiTile(
              label: 'Officers Deployed',
              value: '${kpi['officers_deployed'] ?? 0}',
              icon: Icons.people_alt_outlined,
              color: AppColors.green,
              subtitle: 'Currently on duty',
            ),
            const SizedBox(height: 12),
            KpiTile(
              label: 'Open Complaints',
              value: '${kpi['open_complaints'] ?? 0}',
              icon: Icons.report_gmailerrorred_outlined,
              color: AppColors.amber,
              subtitle: 'Pending review',
            ),
            const SizedBox(height: 12),
            KpiTile(
              label: 'Active Alerts',
              value: '${kpi['active_alerts'] ?? 0}',
              icon: Icons.notifications_active_outlined,
              color: AppColors.red,
              subtitle: 'City-wide',
            ),
          ],
        );
      },
    );
  }

  Widget _buildKpiRow() {
    final role = ref.read(roleProvider);
    final isCitizen = role == AppRole.citizen;
    return ref.watch(kpiProvider).when(
      loading: () => const SkeletonLoader(height: 80),
      error: (_, __) => const SkeletonLoader(height: 80),
      data: (kpi) {
        final tiles = isCitizen
            ? [
                KpiTile(label: 'Events', value: '${kpi['active_events'] ?? 0}', icon: Icons.event_outlined, color: const Color(0xFF2563EB)),
                KpiTile(label: 'Alerts', value: '${kpi['active_alerts'] ?? 0}', icon: Icons.notifications_outlined, color: AppColors.red),
                KpiTile(label: 'Volunteers', value: '${kpi['volunteers_pending'] ?? 0}', icon: Icons.volunteer_activism, color: AppColors.green),
              ]
            : [
                KpiTile(label: 'Events', value: '${kpi['active_events'] ?? 0}', icon: Icons.event_outlined, color: const Color(0xFF2563EB)),
                KpiTile(label: 'Officers', value: '${kpi['officers_deployed'] ?? 0}', icon: Icons.people_alt_outlined, color: AppColors.green),
                KpiTile(label: 'Complaints', value: '${kpi['open_complaints'] ?? 0}', icon: Icons.report_outlined, color: AppColors.amber),
                KpiTile(label: 'Alerts', value: '${kpi['active_alerts'] ?? 0}', icon: Icons.notifications_outlined, color: AppColors.red),
              ];

        return LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 550) {
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: tiles.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.35,
                ),
                itemBuilder: (_, i) => tiles[i],
              );
            }
            return Row(
              children: [
                for (int i = 0; i < tiles.length; i++) ...
                  [
                    Expanded(child: tiles[i]),
                    if (i < tiles.length - 1) const SizedBox(width: 10),
                  ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDeferredMapCard() {
    if (!_mapReady) {
      return const GlassCard(
        height: 420,
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2563EB)),
          ),
        ),
      );
    }
    StartupTimer.mark('Dashboard map rendering');
    return _buildMapCard();
  }

  Widget _buildMapCard() {
    // Zone polygon data (approximated for Bengaluru zones)
    final zoneData = [
      _ZoneData('Central Zone 1', const LatLng(12.978, 77.595), 0.82, [
        const LatLng(12.990, 77.580), const LatLng(12.990, 77.610),
        const LatLng(12.965, 77.610), const LatLng(12.965, 77.580),
      ]),
      _ZoneData('South Zone 1', const LatLng(12.917, 77.623), 0.65, [
        const LatLng(12.930, 77.608), const LatLng(12.930, 77.638),
        const LatLng(12.904, 77.638), const LatLng(12.904, 77.608),
      ]),
      _ZoneData('North Zone 1', const LatLng(13.045, 77.597), 0.48, [
        const LatLng(13.058, 77.582), const LatLng(13.058, 77.612),
        const LatLng(13.032, 77.612), const LatLng(13.032, 77.582),
      ]),
      _ZoneData('East Zone 1', const LatLng(12.969, 77.700), 0.35, [
        const LatLng(12.980, 77.685), const LatLng(12.980, 77.715),
        const LatLng(12.958, 77.715), const LatLng(12.958, 77.685),
      ]),
      _ZoneData('West Zone 1', const LatLng(12.985, 77.507), 0.55, [
        const LatLng(12.998, 77.492), const LatLng(12.998, 77.522),
        const LatLng(12.972, 77.522), const LatLng(12.972, 77.492),
      ]),
    ];

    return GlassCard(
      padding: EdgeInsets.zero,
      height: 420,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapCtrl,
              options: MapOptions(
                initialCenter: const LatLng(12.9716, 77.5946),
                initialZoom: 11.5,
                minZoom: 9,
                maxZoom: 16,
              ),
              children: [
                TileLayer(
                  urlTemplate: AppConfig.mapTileUrl,
                  userAgentPackageName: 'com.preact.preact_app',
                ),
                // Zone polygons
                PolygonLayer(
                  polygons: zoneData.map((z) => Polygon(
                    points: z.polygon,
                    color: AppColors.fromSeverity(z.severity).withOpacity(0.25),
                    borderColor: AppColors.fromSeverity(z.severity),
                    borderStrokeWidth: 2,
                  )).toList(),
                ),
                // Junction markers
                MarkerLayer(
                  markers: AppConstants.junctions.take(6).map((j) => Marker(
                    point: LatLng(j['lat'] as double, j['lng'] as double),
                    width: 32, height: 32,
                    child: GestureDetector(
                      onTap: () => _onJunctionTap(j['name'] as String),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB).withOpacity(0.9),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [BoxShadow(color: const Color(0xFF2563EB).withOpacity(0.5), blurRadius: 8)],
                        ),
                        child: const Icon(Icons.location_on, color: Colors.white, size: 16),
                      ),
                    ),
                  )).toList(),
                ),
              ],
            ),
            // Map legend
            Positioned(
              bottom: 12, left: 12,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.borderDark),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Severity', style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    _legendItem(AppColors.green, 'Low'),
                    _legendItem(AppColors.amber, 'Medium'),
                    _legendItem(AppColors.red, 'High'),
                  ],
                ),
              ),
            ),
            // Map header
            Positioned(
              top: 12, left: 12, right: 12,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceDark.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.circle, color: AppColors.green, size: 8),
                        SizedBox(width: 6),
                        Text('Bengaluru Live', style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceDark.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('OSM · flutter_map', style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendItem(Color c, String label) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
      ],
    ),
  );

  Widget _buildSparklines() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const zones = ['Central Zone 1', 'South Zone 1', 'North Zone 1'];
    final colors = [AppColors.red, AppColors.amber, AppColors.green];
    final values = [
      [0.3, 0.5, 0.7, 0.82, 0.78, 0.65, 0.55],
      [0.2, 0.35, 0.55, 0.65, 0.60, 0.48, 0.40],
      [0.25, 0.30, 0.40, 0.48, 0.45, 0.38, 0.32],
    ];

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Zone Severity Trend',
            style: TextStyle(color: isDark ? AppColors.textPrimary : AppColors.textPrimaryDark, fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          ...List.generate(zones.length, (i) => _sparklineRow(zones[i], values[i], colors[i])),
        ],
      ),
    );
  }

  Widget _sparklineRow(String zone, List<double> data, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(zone, style: TextStyle(color: isDark ? AppColors.textSecondary : AppColors.textSecondaryDark, fontSize: 11), overflow: TextOverflow.ellipsis),
              ),
              Text(
                '${(data.last * 100).toStringAsFixed(0)}%',
                style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 30,
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                minY: 0, maxY: 1,
                lineBarsData: [
                  LineChartBarData(
                    spots: data.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList(),
                    isCurved: true,
                    color: color,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: color.withOpacity(0.1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertFeed() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Live Alerts',
                style: TextStyle(color: isDark ? AppColors.textPrimary : AppColors.textPrimaryDark, fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Container(
                width: 8, height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.red,
                ),
              ),
              const SizedBox(width: 4),
              const Text('LIVE', style: TextStyle(color: AppColors.red, fontSize: 10, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          _buildAlertFeedContent(),
        ],
      ),
    );
  }

  Widget _buildAlertFeedContent() {
    final alertsAsync = ref.watch(alertsProvider);
    debugPrint('[Dashboard] _buildAlertFeedContent: alertsAsync state: ${alertsAsync.runtimeType}');
    return alertsAsync.when(
      skipLoadingOnReload: true,
      loading: () {
        debugPrint('[Dashboard] alertsProvider loading');
        return const SkeletonList(count: 3, cardHeight: 70);
      },
      error: (err, stack) {
        debugPrint('[Dashboard] alertsProvider error: $err, stack: $stack');
        return _alertList(alertsAsync.valueOrNull ?? const []);
      },
      data: (alerts) {
        debugPrint('[Dashboard] alertsProvider data: ${alerts.length} alerts');
        return _alertList(alerts);
      },
    );
  }


  Widget _alertList(List<AlertModel> alerts) {
    final display = alerts.take(4).toList();
    debugPrint('[DEBUG] Dashboard alert count: ${display.length}');
    debugPrint('[DEBUG] Alerts: $display');
    if (display.isEmpty) {
      return const Text(
        'No alerts',
        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < display.length; i++)
          AlertCard(
            key: ValueKey(display[i].id.isNotEmpty ? display[i].id : 'alert-$i'),
            alert: display[i],
          ),
      ],
    );
  }

  Widget _buildVoiceFab() {
    return FloatingActionButton(
      heroTag: 'dash-voice-fab',
      onPressed: () => ref.read(voiceOverlayOpenProvider.notifier).state = true,
      backgroundColor: const Color(0xFF2563EB),
      foregroundColor: AppColors.backgroundDark,
      child: const Icon(Icons.mic_none_rounded),
    );
  }

  void _onJunctionTap(String junctionName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$junctionName — 2 officers assigned, severity: Medium'),
        backgroundColor: AppColors.surfaceElevatedDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

class _InsightCard {
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  const _InsightCard({required this.icon, required this.color, required this.title, required this.body});
}

class _ZoneData {
  final String name;
  final LatLng center;
  final double severity;
  final List<LatLng> polygon;
  const _ZoneData(this.name, this.center, this.severity, this.polygon);
}
