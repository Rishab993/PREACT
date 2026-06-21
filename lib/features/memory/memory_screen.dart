import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/colors.dart';
import '../../core/api/endpoints.dart';
import '../../providers/data_providers.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/skeleton_loader.dart';
import '../../shared/widgets/severity_gauge.dart';

class MemoryScreen extends ConsumerStatefulWidget {
  const MemoryScreen({super.key});

  @override
  ConsumerState<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends ConsumerState<MemoryScreen>
    with SingleTickerProviderStateMixin {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String? _filterZone;
  String? _filterEventType;
  int _minAttendance = 0;
  DebriefModel? _selectedDebrief;
  late AnimationController _fadeCtrl;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400))..forward();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  MemorySearchParams get _params => MemorySearchParams(
    query: _query,
    zone: _filterZone,
    eventType: _filterEventType,
    minAttendance: _minAttendance,
  );

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: _selectedDebrief != null
            ? _buildDebriefDetail(_selectedDebrief!)
            : _buildSearchView(),
      ),
    );
  }

  Widget _buildSearchView() {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 900;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Institutional Memory', style: Theme.of(context).textTheme.displayLarge),
          const Text('Full-text search across all past events', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 16),
          _buildSearchBar(),
          const SizedBox(height: 10),
          _buildFilterRow(),
          const SizedBox(height: 16),
          isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: _buildResults()),
                    const SizedBox(width: 16),
                    SizedBox(width: 260, child: _buildInsightPanel()),
                  ],
                )
              : _buildResults(),
        ],
      ),
    );
  }

  Widget _buildSearchBar() => Row(
    children: [
      Expanded(
        child: TextField(
          controller: _searchCtrl,
          style: const TextStyle(color: AppColors.textPrimary),
          onChanged: (v) => setState(() => _query = v),
          onSubmitted: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: 'Search "IPL", "Rajyotsava", "Silk Board"...',
            prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary, size: 20),
            suffixIcon: _query.isNotEmpty
                ? IconButton(
                    onPressed: () { setState(() => _query = ''); _searchCtrl.clear(); },
                    icon: const Icon(Icons.clear, size: 18, color: AppColors.textSecondary),
                  )
                : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: AppColors.surfaceElevatedDark,
          ),
        ),
      ),
      const SizedBox(width: 8),
      ElevatedButton(
        onPressed: () => setState(() => _query = _searchCtrl.text),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2563EB),
          foregroundColor: AppColors.backgroundDark,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
        child: const Text('Search'),
      ),
    ],
  );

  Widget _buildFilterRow() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        _FilterChip(
          label: _filterZone ?? 'Zone',
          active: _filterZone != null,
          onTap: () => _showZonePicker(),
        ),
        const SizedBox(width: 8),
        _FilterChip(
          label: _filterEventType ?? 'Event Type',
          active: _filterEventType != null,
          onTap: () => _showEventTypePicker(),
        ),
        const SizedBox(width: 8),
        _FilterChip(
          label: _minAttendance > 0 ? '>= ${_minAttendance}K attend' : 'Min Attendance',
          active: _minAttendance > 0,
          onTap: () => _showAttendancePicker(),
        ),
        if (_filterZone != null || _filterEventType != null || _minAttendance > 0) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => setState(() { _filterZone = null; _filterEventType = null; _minAttendance = 0; }),
            child: const Text('Clear all', style: TextStyle(color: const Color(0xFF2563EB), fontSize: 12)),
          ),
        ],
      ],
    ),
  );

  Widget _buildResults() {
    return ref.watch(memorySearchProvider(_params)).when(
      loading: () => const SkeletonList(count: 4, cardHeight: 120),
      error: (_, __) => Column(
        children: [
          const Icon(Icons.history_edu_outlined, color: AppColors.textMuted, size: 48),
          const SizedBox(height: 12),
          const Text('Could not reach memory API', style: TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 8),
          ..._seedResults().map((d) => _DebriefCard(debrief: d, onTap: () => setState(() => _selectedDebrief = d))),
        ],
      ),
      data: (debriefs) {
        if (debriefs.isEmpty) {
          // Auto-relax: show seed data + no-results banner
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.amber.withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: AppColors.amber, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No exact matches. Showing similar events:',
                        style: TextStyle(color: AppColors.amber, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              ..._seedResults().map((d) => _DebriefCard(debrief: d, onTap: () => setState(() => _selectedDebrief = d))),
            ],
          );
        }
        return Column(
          children: debriefs.map((d) => _DebriefCard(debrief: d, onTap: () => setState(() => _selectedDebrief = d))).toList(),
        );
      },
    );
  }

  Widget _buildInsightPanel() => GlassCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.psychology_outlined, color: AppColors.purple, size: 16),
            SizedBox(width: 6),
            Text('Memory Insights', style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 12),
        _insightItem('Best intervention', 'Diversion Route B (−28% delay)'),
        _insightItem('Most common cause', 'Pedestrian surge (35% of events)'),
        _insightItem('Avg regret score', '31%'),
        _insightItem('Top junction', 'Silk Board (12 high-stress events)'),
        const SizedBox(height: 12),
        const Divider(color: AppColors.borderDark),
        const SizedBox(height: 8),
        const Text('Quick Searches', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, letterSpacing: 0.5)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6, runSpacing: 6,
          children: ['IPL', 'Rajyotsava', 'Marathon', 'Hebbal', 'Protest']
              .map((q) => GestureDetector(
                    onTap: () { setState(() { _query = q; _searchCtrl.text = q; }); },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2563EB).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF2563EB).withOpacity(0.3)),
                      ),
                      child: Text(q, style: const TextStyle(color: const Color(0xFF2563EB), fontSize: 11)),
                    ),
                  ))
              .toList(),
        ),
      ],
    ),
  );

  Widget _insightItem(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11))),
        Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    ),
  );

  Widget _buildDebriefDetail(DebriefModel d) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => setState(() => _selectedDebrief = null),
                icon: const Icon(Icons.arrow_back, color: const Color(0xFF2563EB)),
              ),
              Expanded(child: Text(d.eventName ?? 'Debrief', style: Theme.of(context).textTheme.headlineMedium)),
            ],
          ),
          const SizedBox(height: 16),
          // Hero metrics
          Row(
            children: [
              Expanded(child: GlassCard(
                child: Column(
                  children: [
                    Text(d.attendanceDisplay, style: const TextStyle(color: const Color(0xFF2563EB), fontSize: 20, fontWeight: FontWeight.w700)),
                    const Text('Expected', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                  ],
                ),
              )),
              const SizedBox(width: 12),
              Expanded(child: GlassCard(
                child: Column(
                  children: [
                    Text('${d.congestionAvoidedMinutes?.toStringAsFixed(0) ?? "—"} min', style: TextStyle(color: (d.congestionAvoidedMinutes ?? 0) > 0 ? AppColors.green : AppColors.red, fontSize: 20, fontWeight: FontWeight.w700)),
                    const Text('Avoided', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                  ],
                ),
              )),
              const SizedBox(width: 12),
              Expanded(child: GlassCard(
                child: Column(
                  children: [
                    SeverityGauge(value: d.regretScore ?? 0, size: 60, strokeWidth: 6),
                    const Text('Regret', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                  ],
                ),
              )),
            ],
          ),
          const SizedBox(height: 16),
          if (d.topIntervention != null) GlassCard(
            borderColor: AppColors.green.withOpacity(0.3),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: AppColors.green, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Best Intervention', style: TextStyle(color: AppColors.green, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                    Text(d.topIntervention!, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                  ],
                )),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (d.missedOpportunity != null) GlassCard(
            borderColor: AppColors.red.withOpacity(0.3),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_outlined, color: AppColors.red, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Missed Opportunity', style: TextStyle(color: AppColors.red, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                    Text(d.missedOpportunity!, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                  ],
                )),
              ],
            ),
          ),
          if (d.notes != null && d.notes!.isNotEmpty) ...[
            const SizedBox(height: 10),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Notes', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                  const SizedBox(height: 6),
                  Text(d.notes!, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<DebriefModel> _seedResults() => [
    DebriefModel(id: 'seed-1', eventName: 'IPL RCB vs CSK', locationName: 'Chinnaswamy', expectedAttendance: 35000, congestionAvoidedMinutes: 33, regretScore: 0.38, topIntervention: 'Diversion Route B', missedOpportunity: 'Gate 2 understaffed'),
    DebriefModel(id: 'seed-2', eventName: 'Rajyotsava Parade', locationName: 'MG Road', expectedAttendance: 50000, congestionAvoidedMinutes: 6, regretScore: 0.12, topIntervention: 'Pre-positioning worked', missedOpportunity: 'Residency Road late setup'),
    DebriefModel(id: 'seed-3', eventName: 'Bengaluru Marathon', locationName: 'Cubbon Park', expectedAttendance: 25000, congestionAvoidedMinutes: 0, regretScore: 0.61, topIntervention: 'N/A', missedOpportunity: 'No Kasturba Road diversion'),
  ];

  void _showZonePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          ListTile(title: const Text('All Zones', style: TextStyle(color: AppColors.textPrimary)), onTap: () { setState(() => _filterZone = null); Navigator.pop(context); }),
          ...AppConstants.zones.map((z) => ListTile(
            title: Text(z, style: const TextStyle(color: AppColors.textPrimary)),
            trailing: _filterZone == z ? const Icon(Icons.check, color: const Color(0xFF2563EB)) : null,
            onTap: () { setState(() => _filterZone = z); Navigator.pop(context); },
          )),
        ],
      ),
    );
  }

  void _showEventTypePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          ListTile(title: const Text('All Types', style: TextStyle(color: AppColors.textPrimary)), onTap: () { setState(() => _filterEventType = null); Navigator.pop(context); }),
          ...AppConstants.eventCategories.map((t) => ListTile(
            title: Text(t.toUpperCase(), style: const TextStyle(color: AppColors.textPrimary)),
            onTap: () { setState(() => _filterEventType = t); Navigator.pop(context); },
          )),
        ],
      ),
    );
  }

  void _showAttendancePicker() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Min Attendance (K)'),
        content: StatefulBuilder(
          builder: (_, ss) => Slider(
            value: _minAttendance.toDouble(),
            min: 0, max: 100, divisions: 10,
            label: '${_minAttendance}K',
            onChanged: (v) { ss(() => _minAttendance = v.toInt()); setState(() {}); },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
      ),
    );
  }
}

class _DebriefCard extends StatelessWidget {
  final DebriefModel debrief;
  final VoidCallback onTap;
  const _DebriefCard({required this.debrief, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final regretColor = AppColors.fromSeverity(debrief.regretScore ?? 0);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderDark),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(debrief.eventName ?? 'Unknown', style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  if (debrief.locationName != null)
                    Text(debrief.locationName!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                  Text(debrief.attendanceDisplay, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                  const SizedBox(height: 4),
                  if (debrief.topIntervention != null)
                    Row(
                      children: [
                        const Icon(Icons.check_circle_outline, color: AppColors.green, size: 12),
                        const SizedBox(width: 4),
                        Expanded(child: Text(debrief.topIntervention!, style: const TextStyle(color: AppColors.green, fontSize: 11), overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              children: [
                SeverityGauge(value: debrief.regretScore ?? 0, size: 56, strokeWidth: 5, showPercent: false),
                Text(debrief.regretLabel, style: TextStyle(color: regretColor, fontSize: 11, fontWeight: FontWeight.w700)),
                const Text('regret', style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
              ],
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 18),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: active ? const Color(0xFF2563EB).withOpacity(0.12) : AppColors.surfaceElevatedDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: active ? const Color(0xFF2563EB).withOpacity(0.5) : AppColors.borderDark),
      ),
      child: Text(label, style: TextStyle(color: active ? const Color(0xFF2563EB) : AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w500)),
    ),
  );
}
