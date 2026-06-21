import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/colors.dart';
import '../../core/api/endpoints.dart';
import '../../core/api/api_client.dart';
import '../../providers/data_providers.dart';
import '../../providers/app_providers.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/alert_card.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/skeleton_loader.dart';

class AlertsScreen extends ConsumerStatefulWidget {
  const AlertsScreen({super.key});

  @override
  ConsumerState<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends ConsumerState<AlertsScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeCtrl;
  bool _showCreateForm = false;
  final _formKey = GlobalKey<FormState>();
  final _msgCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _issuerCtrl = TextEditingController();
  String _severity = 'medium';
  String _zone = AppConstants.zones.first;
  String _category = 'traffic';
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400))..forward();
    _refreshTimer = Timer.periodic(alertsRefreshInterval, (_) => _refreshAlerts());
  }

  void _refreshAlerts() {
    invalidateAlertsCache();
    ref.invalidate(alertsProvider);
    ref.invalidate(kpiProvider);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _fadeCtrl.dispose();
    _msgCtrl.dispose();
    _titleCtrl.dispose();
    _issuerCtrl.dispose();
    super.dispose();
  }

  Future<void> _createAlert() async {
    if (!_formKey.currentState!.validate()) return;
    final sevVal = _severity == 'high' ? 0.85 : _severity == 'medium' ? 0.55 : 0.3;
    void _resetForm() {
      _showCreateForm = false;
      _msgCtrl.clear();
      _titleCtrl.clear();
      _issuerCtrl.clear();
    }
    try {
      final payload = {
        'zone': _zone,
        'title': _titleCtrl.text.isEmpty ? null : _titleCtrl.text,
        'message_en': _msgCtrl.text,
        'message_kn': _msgCtrl.text,
        'severity': sevVal,
        'category': _category,
        'issuer': _issuerCtrl.text.isEmpty ? 'Traffic Police' : _issuerCtrl.text,
        'valid_from': DateTime.now().toIso8601String(),
        'valid_until': DateTime.now().add(const Duration(hours: 4)).toIso8601String(),
      };

      await ApiClient.instance.post(AppEndpoints.alerts, data: payload);

      invalidateAlertsCache();
      ref.invalidate(alertsProvider);
      ref.invalidate(kpiProvider);
      
      setState(_resetForm);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alert created successfully!'), backgroundColor: AppColors.green),
        );
      }
    } catch (e) {
      debugPrint('[AlertsScreen] Error creating alert: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to create alert'), backgroundColor: AppColors.red),
      );
      setState(_resetForm);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(roleProvider);
    final isCitizen = role == AppRole.citizen;

    return FadeTransition(
      opacity: CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: isCitizen
            ? null
            : FloatingActionButton.extended(
                onPressed: () => setState(() => _showCreateForm = !_showCreateForm),
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                icon: Icon(_showCreateForm ? Icons.close : Icons.add_alert_outlined),
                label: Text(_showCreateForm ? 'Cancel' : 'New Alert'),
              ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context),
                    if (_showCreateForm && !isCitizen) _buildCreateForm(),
                    _buildAlertTimeline(isCitizen),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Alerts', style: Theme.of(context).textTheme.displayLarge),
                  Row(
                    children: [
                      const Icon(Icons.circle, color: AppColors.red, size: 8),
                      const SizedBox(width: 6),
                      const Text('Live · Auto-refresh 15s',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
              onPressed: _refreshAlerts,
            ),
          ],
        ),
      );

  Widget _buildCreateForm() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.all(16),
      child: GlassCard(
        borderColor: const Color(0xFF2563EB).withOpacity(0.4),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Create Alert',
                  style: TextStyle(color: isDark ? AppColors.textPrimary : AppColors.textPrimaryDark, fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              // Title
              TextFormField(
                controller: _titleCtrl,
                style: TextStyle(color: isDark ? AppColors.textPrimary : AppColors.textPrimaryDark),
                decoration: InputDecoration(
                  labelText: 'Alert Title',
                  hintText: 'e.g. Silk Board congestion warning',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 10),
              // Zone + Category row
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _zone,
                      decoration: InputDecoration(
                          labelText: 'Zone', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                      dropdownColor: isDark ? AppColors.surfaceElevatedDark : AppColors.surfaceElevatedLight,
                      style: TextStyle(color: isDark ? AppColors.textPrimary : AppColors.textPrimaryDark, fontSize: 13),
                      items: AppConstants.zones.map((z) => DropdownMenuItem(value: z, child: Text(z, style: const TextStyle(fontSize: 13)))).toList(),
                      onChanged: (z) => setState(() => _zone = z!),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _category,
                      decoration: InputDecoration(
                          labelText: 'Category', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                      dropdownColor: isDark ? AppColors.surfaceElevatedDark : AppColors.surfaceElevatedLight,
                      style: TextStyle(color: isDark ? AppColors.textPrimary : AppColors.textPrimaryDark, fontSize: 13),
                      items: const [
                        DropdownMenuItem(value: 'traffic', child: Text('Traffic', style: TextStyle(fontSize: 13))),
                        DropdownMenuItem(value: 'event', child: Text('Event', style: TextStyle(fontSize: 13))),
                        DropdownMenuItem(value: 'emergency', child: Text('Emergency', style: TextStyle(fontSize: 13))),
                        DropdownMenuItem(value: 'weather', child: Text('Weather', style: TextStyle(fontSize: 13))),
                        DropdownMenuItem(value: 'road_work', child: Text('Road Work', style: TextStyle(fontSize: 13))),
                      ],
                      onChanged: (c) => setState(() => _category = c!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Severity
              Row(
                children: ['low', 'medium', 'high']
                    .map((s) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(s.toUpperCase()),
                            selected: _severity == s,
                            onSelected: (_) => setState(() => _severity = s),
                            selectedColor: s == 'high'
                                ? AppColors.red.withOpacity(0.2)
                                : s == 'medium'
                                    ? AppColors.amber.withOpacity(0.2)
                                    : AppColors.green.withOpacity(0.2),
                            labelStyle: TextStyle(
                              color: _severity == s
                                  ? (s == 'high' ? AppColors.red : s == 'medium' ? AppColors.amber : AppColors.green)
                                  : AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _msgCtrl,
                style: TextStyle(color: isDark ? AppColors.textPrimary : AppColors.textPrimaryDark),
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Alert Message (English)',
                  hintText: 'e.g. Heavy congestion near Silk Board...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                validator: (v) => v == null || v.isEmpty ? 'Message required' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _issuerCtrl,
                style: TextStyle(color: isDark ? AppColors.textPrimary : AppColors.textPrimaryDark),
                decoration: InputDecoration(
                  labelText: 'Issuer / Authority',
                  hintText: 'e.g. Bengaluru Traffic Police, Control Room',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _createAlert,
                  child: const Text('Create Alert'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAlertTimeline(bool isCitizen) {
    return RefreshIndicator(
      onRefresh: () async {
        invalidateAlertsCache();
        ref.invalidate(alertsProvider);
        try {
          await ref.read(alertsProvider.future);
        } catch (_) {}
      },
      child: ref.watch(alertsProvider).when(
            skipLoadingOnReload: true,
            loading: () => const Padding(
                padding: EdgeInsets.all(16), child: SkeletonList(count: 5, cardHeight: 80)),
            error: (err, _) {
              debugPrint('[AlertsScreen] load error: $err');
              final cached = ref.read(alertsProvider).valueOrNull ?? const <AlertModel>[];
              if (cached.isEmpty) {
                return const Center(
                  child: Text('Could not load alerts', style: TextStyle(color: AppColors.textMuted)),
                );
              }
              return _buildList(cached, isCitizen);
            },
            data: (alerts) => _buildList(alerts, isCitizen),
          ),
    );
  }

  Widget _buildList(List<AlertModel> alerts, bool isCitizen) {
    final displayAlerts = alerts;
    debugPrint('[DEBUG] Alerts screen alert count: ${displayAlerts.length}');
    final showBanner = alerts.isEmpty;

    return Column(
      children: [
        if (showBanner)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.amber.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.amber.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: AppColors.amber, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No alerts from the server yet.',
                      style: TextStyle(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? AppColors.textPrimary
                            : AppColors.textPrimaryDark,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: displayAlerts.length,
          itemBuilder: (_, i) {
            final alert = displayAlerts[i];
            return AlertCard(
              key: ValueKey(alert.id.isNotEmpty ? alert.id : 'alert-$i'),
              alert: alert,
              onDismiss: null,
            );
          },
        ),
      ],
    );
  }
}
