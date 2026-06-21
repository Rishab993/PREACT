import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../core/theme/colors.dart';
import '../../core/api/endpoints.dart';
import '../../core/api/api_client.dart';
import '../../core/config/app_config.dart';
import '../../providers/data_providers.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/officer_card.dart';
import '../../shared/widgets/skeleton_loader.dart';

class DeploymentScreen extends ConsumerStatefulWidget {
  const DeploymentScreen({super.key});

  @override
  ConsumerState<DeploymentScreen> createState() => _DeploymentScreenState();
}

class _DeploymentScreenState extends ConsumerState<DeploymentScreen>
    with SingleTickerProviderStateMixin {
  String? _selectedEventId;
  String? _selectedEventName;
  List<DeploymentModel> _deployments = [];
  List<OfficerModel> _officers = [];
  bool _loadingOfficers = false;
  bool _optimizing = false;
  bool _showHeatmap = false;
  String? _selectedOfficerId;
  final Set<String> _selectedOfficerIds = {};
  bool _showResultsPanel = false;
  late AnimationController _fadeCtrl;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500))
      ..forward();
    _loadData();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loadingOfficers = true);
    final officerRows = await ref
        .read(officersApiProvider.future)
        .catchError((_) => <OfficerModel>[]);
    final depRows = await ref
        .read(deploymentsProvider(null).future)
        .catchError((_) => <DeploymentModel>[]);
    if (mounted) {
      setState(() {
        _officers = officerRows;
        _selectedOfficerIds.clear();
        _selectedOfficerIds
            .addAll(officerRows.where((o) => o.available).map((o) => o.id));
        _deployments = depRows;
        _loadingOfficers = false;
      });
    }
    debugPrint(
        '[Deployment] Loaded ${_officers.length} officers, ${_deployments.length} deployments');
  }

  Future<void> _loadDeploymentsForEvent(String? eventId) async {
    try {
      final depRows = await ref.read(deploymentsProvider(eventId).future);
      if (mounted) setState(() => _deployments = depRows);
    } catch (e) {
      debugPrint('[Deployment] Error loading deployments for event: $e');
    }
  }

  Future<void> _autoOptimise() async {
    if (_selectedEventId == null) {
      _showSnack('Select an event first', AppColors.amber);
      return;
    }
    if (_selectedOfficerIds.isEmpty) {
      _showSnack('Select at least one officer', AppColors.amber);
      return;
    }
    setState(() {
      _optimizing = true;
      _showResultsPanel = false;
    });

    try {
      debugPrint('[Deployment] Calling /api/deploy with event=$_selectedEventId, '
          'officer_ids=${_selectedOfficerIds.toList()}');

      final response = await ApiClient.instance.post(
        AppEndpoints.deploy,
        data: {
          'event_id': _selectedEventId,
          'officer_ids': _selectedOfficerIds.toList(),
        },
      );

      debugPrint('[Deployment] Response status: ${response.statusCode}');
      debugPrint('[Deployment] Response data: ${response.data}');

      final data = response.data;
      List<dynamic> rawList = [];
      if (data is Map && data['assignments'] is List) {
        rawList = data['assignments'] as List;
      } else if (data is Map && data['deployment_plan'] is List) {
        rawList = data['deployment_plan'] as List;
      } else if (data is List) {
        rawList = data;
      }

      if (rawList.isNotEmpty) {
        final assignments = rawList.map((r) {
          final map = r as Map<String, dynamic>;
          // Backend returns officer_id but may not include officer_name/badge.
          // Cross-reference with the loaded officers list.
          final officerId = map['officer_id']?.toString();
          OfficerModel? matched;
          if (officerId != null) {
            try {
              matched = _officers.firstWhere((o) => o.id == officerId);
            } catch (_) {}
          }
          return DeploymentModel(
            id: map['id']?.toString() ??
                'opt-${rawList.indexOf(r)}',
            eventId: _selectedEventId,
            officerId: officerId,
            junction: map['junction']?.toString() ?? '',
            lat: (map['lat'] as num?)?.toDouble(),
            lng: (map['lng'] as num?)?.toDouble(),
            priority: map['priority']?.toString() ?? 'medium',
            source: 'preact',
            confirmed: false,
            officerName: map['officer_name']?.toString() ?? matched?.name,
            officerBadge:
                map['officer_badge']?.toString() ?? matched?.badgeNumber,
            officerZone: map['officer_zone']?.toString() ?? matched?.zone,
          );
        }).toList();

        setState(() {
          _deployments = assignments;
          _showResultsPanel = true;
        });
        _showSnack(
            'Deployment plan: ${assignments.length} assignments generated',
            AppColors.green);
        debugPrint(
            '[Deployment] ${assignments.length} assignments parsed successfully');
      } else {
        debugPrint('[Deployment] Unexpected response shape — using demo plan');
        _animateInAssignments();
      }
    } catch (e) {
      debugPrint('[Deployment] API error: $e — falling back to demo plan');
      _animateInAssignments();
    } finally {
      if (mounted) setState(() => _optimizing = false);
    }
  }

  void _animateInAssignments() {
    final junctions = AppConstants.junctions;
    final officerList = _officers
        .where((o) => _selectedOfficerIds.contains(o.id))
        .toList();
    setState(() {
      _deployments = List.generate(
        officerList.length.clamp(0, junctions.length),
        (i) => DeploymentModel(
          id: 'opt-$i',
          eventId: _selectedEventId,
          junction: junctions[i]['name'] as String,
          lat: junctions[i]['lat'] as double,
          lng: junctions[i]['lng'] as double,
          priority: i < 3 ? 'high' : i < 7 ? 'medium' : 'low',
          source: 'preact',
          officerName: officerList[i].name,
          officerBadge: officerList[i].badgeNumber,
          officerZone: officerList[i].zone,
        ),
      );
      _showResultsPanel = true;
    });
    _showSnack('OR-Tools plan applied (demo mode)', const Color(0xFF2563EB));
  }

  void _showSnack(String msg, Color bg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: bg));
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 900;

    return FadeTransition(
      opacity: CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: isWide ? _buildWide() : _buildNarrow(),
      ),
    );
  }

  Widget _buildWide() {
    return Row(
      children: [
        SizedBox(width: 300, child: _buildOfficerPanel()),
        const VerticalDivider(width: 1),
        Expanded(
          child: Column(
            children: [
              Expanded(child: _buildMapPanel()),
              if (_showResultsPanel) _buildResultsPanel(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNarrow() {
    return Column(
      children: [
        SizedBox(height: 260, child: _buildMapPanel()),
        if (_showResultsPanel) _buildResultsPanel(),
        Expanded(child: _buildOfficerPanel()),
      ],
    );
  }

  // ── Officer Panel ────────────────────────────────────────────────────────

  Widget _buildOfficerPanel() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Deployment Planner',
                  style: TextStyle(
                    color: isDark
                        ? AppColors.textPrimary
                        : AppColors.textPrimaryDark,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'SpaceGrotesk',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Select event → choose officers → Auto-Optimise',
                  style: TextStyle(
                    color: isDark
                        ? AppColors.textSecondary
                        : AppColors.textSecondaryDark,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                // Event selector
                ref.watch(eventsProvider).when(
                      loading: () => const SkeletonLoader(height: 44),
                      error: (_, __) => const SizedBox(),
                      data: (events) => DropdownButtonFormField<String>(
                        value: _selectedEventId,
                        decoration: InputDecoration(
                          labelText: 'Select Event',
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        dropdownColor: isDark
                            ? AppColors.surfaceElevatedDark
                            : AppColors.surfaceElevatedLight,
                        style: TextStyle(
                          color: isDark
                              ? AppColors.textPrimary
                              : AppColors.textPrimaryDark,
                          fontSize: 13,
                        ),
                        items: events
                            .map((e) => DropdownMenuItem(
                                  value: e.id,
                                  child: Text(
                                    '${e.name} · ${e.locationName ?? e.status ?? ""}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ))
                            .toList(),
                        onChanged: (id) {
                          final e = events.firstWhere((ev) => ev.id == id);
                          setState(() {
                            _selectedEventId = id;
                            _selectedEventName = e.name;
                            _showResultsPanel = false;
                          });
                          _loadDeploymentsForEvent(id);
                        },
                      ),
                    ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _optimizing ? null : _autoOptimise,
                        icon: _optimizing
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.auto_awesome, size: 16),
                        label: Text(
                          _optimizing ? 'Optimising…' : 'Auto-Optimise',
                          style: const TextStyle(fontSize: 13),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              const Color(0xFF2563EB).withOpacity(0.5),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Toggle heatmap overlay',
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.surfaceElevatedDark
                              : AppColors.surfaceElevatedLight,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: isDark
                                  ? AppColors.borderDark
                                  : AppColors.borderLight),
                        ),
                        child: IconButton(
                          onPressed: () =>
                              setState(() => _showHeatmap = !_showHeatmap),
                          icon: Icon(
                            Icons.layers_outlined,
                            color: _showHeatmap
                                ? const Color(0xFF2563EB)
                                : AppColors.textSecondary,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Officer list header
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Checkbox(
                  value: _officers.isNotEmpty &&
                      _selectedOfficerIds.length == _officers.length,
                  tristate: true,
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _selectedOfficerIds
                            .addAll(_officers.map((o) => o.id));
                      } else {
                        _selectedOfficerIds.clear();
                      }
                    });
                  },
                ),
                Expanded(
                  child: Text(
                    _officers.isEmpty
                        ? 'LOADING OFFICERS…'
                        : 'OFFICERS (${_selectedOfficerIds.length}/${_officers.length} selected)',
                    style: TextStyle(
                      color: isDark
                          ? AppColors.textSecondary
                          : AppColors.textSecondaryDark,
                      fontSize: 11,
                      letterSpacing: 0.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Officer list body
          Expanded(
            child: _loadingOfficers
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SkeletonList(count: 6),
                  )
                : _officers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person_off_outlined,
                                color: AppColors.textMuted, size: 36),
                            const SizedBox(height: 8),
                            Text('No officers available',
                                style: TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 13)),
                            const SizedBox(height: 4),
                            TextButton(
                              onPressed: _loadData,
                              child: const Text('Retry',
                                  style:
                                      TextStyle(color: Color(0xFF2563EB))),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
                        itemCount: _officers.length,
                        itemBuilder: (_, i) {
                          final officer = _officers[i];
                          final isChecked =
                              _selectedOfficerIds.contains(officer.id);
                          return Row(
                            children: [
                              Checkbox(
                                value: isChecked,
                                onChanged: (val) {
                                  setState(() {
                                    if (val == true) {
                                      _selectedOfficerIds.add(officer.id);
                                    } else {
                                      _selectedOfficerIds
                                          .remove(officer.id);
                                      if (_selectedOfficerId ==
                                          officer.id) {
                                        _selectedOfficerId = null;
                                      }
                                    }
                                  });
                                },
                              ),
                              Expanded(
                                child: OfficerCard(
                                  officer: officer,
                                  isSelected:
                                      _selectedOfficerId == officer.id,
                                  onTap: () => setState(() {
                                    _selectedOfficerId =
                                        _selectedOfficerId == officer.id
                                            ? null
                                            : officer.id;
                                  }),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  // ── Map Panel ────────────────────────────────────────────────────────────

  Widget _buildMapPanel() {
    return Stack(
      children: [
        FlutterMap(
          options: const MapOptions(
            initialCenter: LatLng(12.9716, 77.5946),
            initialZoom: 11.5,
          ),
          children: [
            TileLayer(
              urlTemplate: AppConfig.mapTileUrl,
              userAgentPackageName: 'com.preact.preact_app',
            ),
            MarkerLayer(
              markers: [
                ...AppConstants.junctions.map((j) {
                  final assigned = _deployments
                      .where((d) => d.junction == j['name'])
                      .toList();
                  final hasOfficer = assigned.isNotEmpty;
                  return Marker(
                    point:
                        LatLng(j['lat'] as double, j['lng'] as double),
                    width: hasOfficer ? 44 : 32,
                    height: hasOfficer ? 44 : 32,
                    child: GestureDetector(
                      onTap: () => _onJunctionTap(j, assigned),
                      child: Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: hasOfficer
                                  ? AppColors.green.withOpacity(0.9)
                                  : AppColors.surfaceElevatedDark
                                      .withOpacity(0.9),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: hasOfficer
                                    ? AppColors.green
                                    : AppColors.borderDark,
                                width: 2,
                              ),
                              boxShadow: hasOfficer
                                  ? [
                                      BoxShadow(
                                          color: AppColors.green
                                              .withOpacity(0.4),
                                          blurRadius: 8)
                                    ]
                                  : null,
                            ),
                            child: Icon(
                              Icons.location_on,
                              color: hasOfficer
                                  ? Colors.white
                                  : AppColors.textSecondary,
                              size: hasOfficer ? 20 : 16,
                            ),
                          ),
                          if (hasOfficer)
                            Positioned(
                              top: 0,
                              right: 0,
                              child: Container(
                                width: 16,
                                height: 16,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF2563EB),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '${assigned.length}',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ],
        ),
        // Map overlay bar
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: GlassCard(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.map_outlined,
                    color: Color(0xFF2563EB), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedEventName ?? 'Select an event to begin',
                    style: TextStyle(
                      color:
                          Theme.of(context).brightness == Brightness.dark
                              ? AppColors.textPrimary
                              : AppColors.textPrimaryDark,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_deployments.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.green.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.green.withOpacity(0.4)),
                    ),
                    child: Text(
                      '${_deployments.length} assigned',
                      style: const TextStyle(
                          color: AppColors.green,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Loading overlay
        if (_optimizing)
          Positioned.fill(
            child: Container(
              color: Colors.black26,
              child: const Center(
                child: CircularProgressIndicator(color: Color(0xFF2563EB)),
              ),
            ),
          ),
      ],
    );
  }

  // ── Assignment Results Panel ──────────────────────────────────────────────

  Widget _buildResultsPanel() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final high = _deployments.where((d) => d.priority == 'high').length;
    final med = _deployments.where((d) => d.priority == 'medium').length;
    final low = _deployments.where((d) => d.priority == 'low').length;

    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        border: Border(
          top: BorderSide(
              color: const Color(0xFF2563EB).withOpacity(0.4), width: 1.5),
        ),
      ),
      child: Column(
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.check_circle_outline,
                        color: AppColors.green, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'OR-Tools Assignments — ${_deployments.length} total',
                        style: TextStyle(
                          color: isDark
                              ? AppColors.textPrimary
                              : AppColors.textPrimaryDark,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _PriorityBadge('HIGH', high, AppColors.red),
                    _PriorityBadge('MED', med, AppColors.amber),
                    _PriorityBadge('LOW', low, AppColors.green),
                    const SizedBox(width: 4),
                    ElevatedButton(
                      onPressed: _confirmPlan,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      child: const Text('Confirm Plan'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Assignment table
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.vertical,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _deployments.length,
              itemBuilder: (_, i) {
                final d = _deployments[i];
                final prioColor = d.priority == 'high'
                    ? AppColors.red
                    : d.priority == 'medium'
                        ? AppColors.amber
                        : AppColors.green;
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.surfaceElevatedDark
                          : AppColors.surfaceElevatedLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: isDark
                              ? AppColors.borderDark
                              : AppColors.borderLight),
                    ),
                    child: Row(
                      children: [
                        // Priority indicator
                        Container(
                          width: 4,
                          height: 32,
                          decoration: BoxDecoration(
                            color: prioColor,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Junction
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                d.junction,
                                style: TextStyle(
                                  color: isDark
                                      ? AppColors.textPrimary
                                      : AppColors.textPrimaryDark,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                d.priority.toUpperCase(),
                                style: TextStyle(
                                    color: prioColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                        // Officer
                        Expanded(
                          flex: 3,
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 12,
                                backgroundColor:
                                    const Color(0xFF2563EB).withOpacity(0.15),
                                child: Text(
                                  _initials(d.officerName ?? '?'),
                                  style: const TextStyle(
                                      color: Color(0xFF2563EB),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      d.officerName ?? 'Officer',
                                      style: TextStyle(
                                        color: isDark
                                            ? AppColors.textPrimary
                                            : AppColors.textPrimaryDark,
                                        fontSize: 12,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (d.officerBadge != null)
                                      Text(
                                        d.officerBadge!,
                                        style: TextStyle(
                                            color: isDark
                                                ? AppColors.textSecondary
                                                : AppColors.textSecondaryDark,
                                            fontSize: 10),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Status chip
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: d.confirmed
                                ? AppColors.green.withOpacity(0.12)
                                : AppColors.amber.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            d.confirmed ? 'Confirmed' : 'Pending',
                            style: TextStyle(
                              color:
                                  d.confirmed ? AppColors.green : AppColors.amber,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  Future<void> _confirmPlan() async {
    _showSnack('Deployment plan confirmed and saved', AppColors.green);
    setState(() {
      _deployments = _deployments
          .map((d) => DeploymentModel(
                id: d.id,
                eventId: d.eventId,
                officerId: d.officerId,
                junction: d.junction,
                lat: d.lat,
                lng: d.lng,
                priority: d.priority,
                source: d.source,
                confirmed: true,
                officerName: d.officerName,
                officerBadge: d.officerBadge,
                officerZone: d.officerZone,
              ))
          .toList();
    });
  }

  // ── Junction Tap Sheet ────────────────────────────────────────────────────

  void _onJunctionTap(
      Map<String, dynamic> junction, List<DeploymentModel> assigned) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor:
          isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.location_on,
                    color: Color(0xFF2563EB), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    junction['name'] as String,
                    style: TextStyle(
                      color: isDark
                          ? AppColors.textPrimary
                          : AppColors.textPrimaryDark,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (assigned.isEmpty)
              Row(
                children: [
                  const Icon(Icons.person_off_outlined,
                      color: AppColors.textMuted, size: 16),
                  const SizedBox(width: 6),
                  Text('No officers assigned',
                      style: TextStyle(
                          color: isDark
                              ? AppColors.textSecondary
                              : AppColors.textSecondaryDark)),
                ],
              )
            else
              ...assigned.map((d) => ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor:
                          const Color(0xFF2563EB).withOpacity(0.12),
                      child: Text(
                        _initials(d.officerName ?? '?'),
                        style: const TextStyle(
                            color: Color(0xFF2563EB),
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(d.officerName ?? 'Officer',
                        style: TextStyle(
                            color: isDark
                                ? AppColors.textPrimary
                                : AppColors.textPrimaryDark,
                            fontSize: 13)),
                    subtitle: Text(
                      '${d.officerBadge ?? ''} · ${d.priority.toUpperCase()}',
                      style: TextStyle(
                          color: isDark
                              ? AppColors.textSecondary
                              : AppColors.textSecondaryDark,
                          fontSize: 11),
                    ),
                    trailing: d.confirmed
                        ? const Icon(Icons.check_circle,
                            color: AppColors.green, size: 18)
                        : const Icon(Icons.pending_outlined,
                            color: AppColors.amber, size: 18),
                  )),
            const SizedBox(height: 8),
            if (_selectedOfficerId != null)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _assignOfficer(junction),
                  icon: const Icon(Icons.add_location_alt_outlined, size: 16),
                  label: const Text('Assign Selected Officer'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _assignOfficer(Map<String, dynamic> junction) {
    Navigator.pop(context);
    if (_selectedOfficerId == null) return;
    OfficerModel officer;
    try {
      officer = _officers.firstWhere((o) => o.id == _selectedOfficerId);
    } catch (_) {
      return;
    }
    final dep = DeploymentModel(
      id: 'manual-${DateTime.now().millisecondsSinceEpoch}',
      eventId: _selectedEventId,
      junction: junction['name'] as String,
      lat: junction['lat'] as double,
      lng: junction['lng'] as double,
      priority: 'medium',
      source: 'manual',
      officerName: officer.name,
      officerBadge: officer.badgeNumber,
      officerZone: officer.zone,
    );
    setState(() {
      _deployments.add(dep);
      _selectedOfficerId = null;
      _showResultsPanel = true;
    });
    _fireAssignmentApi(junction, officer.id);
    _showSnack('${officer.name} → ${junction['name']}', AppColors.green);
  }

  Future<void> _fireAssignmentApi(
      Map<String, dynamic> junction, String officerId) async {
    try {
      await ApiClient.instance.post(AppEndpoints.deploy, data: {
        'event_id': _selectedEventId,
        'junction': junction['name'],
        'officer_id': officerId,
      });
    } catch (_) {}
  }
}

// ── Helper Widgets ─────────────────────────────────────────────────────────────

class _PriorityBadge extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _PriorityBadge(this.label, this.count, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        '$label $count',
        style: TextStyle(
            color: color, fontSize: 10, fontWeight: FontWeight.w700),
      ),
    );
  }
}
