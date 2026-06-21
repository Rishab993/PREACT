import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/colors.dart';
import '../../core/api/endpoints.dart';
import '../../core/api/api_client.dart';
import '../../providers/data_providers.dart';
import '../../providers/app_providers.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/skeleton_loader.dart';

class VolunteerScreen extends ConsumerStatefulWidget {
  const VolunteerScreen({super.key});

  @override
  ConsumerState<VolunteerScreen> createState() => _VolunteerScreenState();
}

class _VolunteerScreenState extends ConsumerState<VolunteerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<VolunteerModel> _volunteers = [];
  bool _isLoading = false;

  // Signup form
  final _signupKey = GlobalKey<FormState>();
  final _citizenIdCtrl = TextEditingController();
  String _signupJunction = AppConstants.junctions.first['name'] as String;
  DateTime _signupDate = DateTime.now().add(const Duration(days: 1));
  String _signupStart = '08:00:00';
  String _signupEnd = '12:00:00';
  bool _isSigningUp = false;
  String? _lastSignupMessage;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _loadVolunteers();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _citizenIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadVolunteers() async {
    setState(() => _isLoading = true);
    try {
      ref.invalidate(volunteersProvider(null));
      final rows = await ref.read(volunteersProvider(null).future);
      if (mounted) setState(() => _volunteers = rows);
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  List<VolunteerModel> _filtered(String status) =>
      _volunteers.where((v) => v.status == status).toList();

  Future<void> _approve(VolunteerModel v) async {
    try {
      await ApiClient.instance.patch('${AppEndpoints.volunteerById(v.id)}', data: {'status': 'approved'});
    } catch (_) {}
    _refreshOne(v, 'approved');
  }

  Future<void> _reject(VolunteerModel v) async {
    try {
      await ApiClient.instance.patch('${AppEndpoints.volunteerById(v.id)}', data: {'status': 'rejected'});
    } catch (_) {}
    _refreshOne(v, 'rejected');
  }

  void _refreshOne(VolunteerModel v, String status) {
    setState(() {
      final idx = _volunteers.indexWhere((x) => x.id == v.id);
      if (idx >= 0) {
        _volunteers[idx] = VolunteerModel(
          id: v.id,
          citizenId: v.citizenId,
          junction: v.junction,
          date: v.date,
          startTime: v.startTime,
          endTime: v.endTime,
          status: status,
        );
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Volunteer $status'), backgroundColor: status == 'approved' ? AppColors.green : AppColors.red),
    );
  }

  Future<void> _signup() async {
    if (!_signupKey.currentState!.validate()) return;
    setState(() => _isSigningUp = true);
    try {
      final response = await ApiClient.instance.post(AppEndpoints.volunteerSignup, data: {
        'citizen_id': _citizenIdCtrl.text.trim(),
        'date': _signupDate.toIso8601String().split('T')[0],
        'start_time': _signupStart.length == 5 ? '$_signupStart:00' : _signupStart,
        'end_time': _signupEnd.length == 5 ? '$_signupEnd:00' : _signupEnd,
        'junction': _signupJunction,
      });

      final message = response.data is Map
          ? (response.data['message']?.toString() ??
              response.data['detail']?.toString() ??
              response.data.toString())
          : response.data?.toString() ?? 'Signup submitted';

      setState(() {
        _isSigningUp = false;
        _lastSignupMessage = message;
      });

      _loadVolunteers();
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Backend Response'),
            content: Text(message),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('[VolunteerScreen] Signup error: $e');
      setState(() => _isSigningUp = false);
      if (mounted) {
        final errStr = e.toString();
        String friendlyMsg;
        if (errStr.contains('foreign key') || errStr.contains('fk_') || errStr.contains('violates foreign key')) {
          friendlyMsg = 'Citizen ID was not recognised by the server.';
        } else if (errStr.contains('duplicate') || errStr.contains('already exists') || errStr.contains('unique')) {
          friendlyMsg = 'You already have a pending signup for this slot.';
        } else if (errStr.contains('timeout') || errStr.contains('timed out')) {
          friendlyMsg = 'Server is slow. Please try again shortly.';
        } else {
          friendlyMsg = 'Signup failed: ${errStr.length > 100 ? errStr.substring(0, 100) : errStr}';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyMsg), backgroundColor: AppColors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(roleProvider);
    final isCitizen = role == AppRole.citizen;

    if (isCitizen) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              const SizedBox(height: 16),
              _buildSignupForm(),
              if (_lastSignupMessage != null) ...[
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.hourglass_top, color: AppColors.amber),
                    title: const Text('Backend Response'),
                    subtitle: Text(_lastSignupMessage!),
                  ),
                ),
              ],
              const SizedBox(height: 40),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _buildVolunteerList('pending'),
                _buildVolunteerList('approved'),
                _buildVolunteerList('rejected'),
              ],
            ),
          ),
        ],
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
              Text('Volunteers', style: Theme.of(context).textTheme.displayLarge),
              const Text('Community traffic helpers', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ],
          ),
        ),
        IconButton(onPressed: _loadVolunteers, icon: const Icon(Icons.refresh_outlined, color: Color(0xFF2563EB))),
      ],
    ),
  );

  Widget _buildTabBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceElevatedDark : AppColors.surfaceElevatedLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: TabBar(
        controller: _tabCtrl,
        indicator: BoxDecoration(
          color: const Color(0xFF2563EB).withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF2563EB).withOpacity(0.4)),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: const Color(0xFF2563EB),
        unselectedLabelColor: isDark ? AppColors.textSecondary : AppColors.textSecondaryDark,
        tabs: [
          Tab(text: 'Pending (${_filtered("pending").length})'),
          Tab(text: 'Active (${_filtered("approved").length})'),
          Tab(text: 'Rejected (${_filtered("rejected").length})'),
        ],
      ),
    );
  }

  Widget _buildSignupForm() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final role = ref.read(roleProvider);
    final isCitizen = role == AppRole.citizen;
    
    return Padding(
      padding: isCitizen ? EdgeInsets.zero : const EdgeInsets.all(16),
      child: Card(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: isDark ? AppColors.borderDark : AppColors.borderLight),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _signupKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Volunteer Signup', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('Assist Bengaluru Traffic Police at busy junctions.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 24),

                // Citizen ID is auto-assigned — read-only display
                TextFormField(
                  controller: _citizenIdCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Citizen ID *',
                    hintText: 'Enter your backend citizen_id',
                  ),
                  style: TextStyle(
                    color: isDark ? AppColors.textPrimary : AppColors.textPrimaryDark,
                    fontSize: 13,
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Citizen ID required'
                      : null,
                ),
                const SizedBox(height: 16),

                DropdownButtonFormField<String>(
                  value: _signupJunction,
                  decoration: const InputDecoration(labelText: 'Junction *'),
                  dropdownColor: isDark ? AppColors.surfaceElevatedDark : AppColors.surfaceElevatedLight,
                  style: TextStyle(color: isDark ? AppColors.textPrimary : AppColors.textPrimaryDark),
                  items: AppConstants.junctions.map((j) => DropdownMenuItem(value: j['name'] as String, child: Text(j['name'] as String))).toList(),
                  onChanged: (v) => setState(() => _signupJunction = v!),
                ),
                const SizedBox(height: 16),
                
                LayoutBuilder(
                  builder: (context, constraints) {
                    final itemWidth = constraints.maxWidth < 620
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 24) / 3;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                    // Date
                    SizedBox(
                      width: itemWidth,
                      child: InkWell(
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _signupDate,
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 30)),
                          );
                          if (date != null) setState(() => _signupDate = date);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'Date'),
                          child: Text(
                            '${_signupDate.day}/${_signupDate.month}/${_signupDate.year}',
                            style: TextStyle(color: isDark ? AppColors.textPrimary : AppColors.textPrimaryDark, fontSize: 13),
                          ),
                        ),
                      ),
                    ),
                    // Start
                    SizedBox(
                      width: itemWidth,
                      child: DropdownButtonFormField<String>(
                        value: _signupStart,
                        decoration: const InputDecoration(labelText: 'Start Time'),
                        dropdownColor: isDark ? AppColors.surfaceElevatedDark : AppColors.surfaceElevatedLight,
                        style: TextStyle(color: isDark ? AppColors.textPrimary : AppColors.textPrimaryDark),
                        items: ['06:00:00','08:00:00','10:00:00','12:00:00','14:00:00','16:00:00','18:00:00']
                            .map((t) => DropdownMenuItem(value: t, child: Text(t.substring(0, 5))))
                            .toList(),
                        onChanged: (v) => setState(() => _signupStart = v!),
                      ),
                    ),
                    // End
                    SizedBox(
                      width: itemWidth,
                      child: DropdownButtonFormField<String>(
                        value: _signupEnd,
                        decoration: const InputDecoration(labelText: 'End Time'),
                        dropdownColor: isDark ? AppColors.surfaceElevatedDark : AppColors.surfaceElevatedLight,
                        style: TextStyle(color: isDark ? AppColors.textPrimary : AppColors.textPrimaryDark),
                        items: ['08:00:00','10:00:00','12:00:00','14:00:00','16:00:00','18:00:00','20:00:00','22:00:00']
                            .map((t) => DropdownMenuItem(value: t, child: Text(t.substring(0, 5))))
                            .toList(),
                        onChanged: (v) => setState(() => _signupEnd = v!),
                      ),
                    ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),
                
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isSigningUp ? null : _signup,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                    ),
                    child: _isSigningUp
                        ? const CircularProgressIndicator(strokeWidth: 2, color: Colors.white)
                        : const Text('Submit Signup', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVolunteerList(String status) {
    if (_isLoading) return const Padding(padding: EdgeInsets.all(16), child: SkeletonList(count: 4));
    final items = _filtered(status);
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.volunteer_activism_outlined, color: AppColors.textMuted, size: 48),
            const SizedBox(height: 12),
            Text('No ${status == "pending" ? "pending" : status == "approved" ? "active" : "rejected"} volunteers', style: const TextStyle(color: AppColors.textMuted)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: items.length,
      itemBuilder: (_, i) => _VolunteerCard(
        volunteer: items[i],
        onApprove: status == 'pending' ? () => _approve(items[i]) : null,
        onReject: status == 'pending' ? () => _reject(items[i]) : null,
      ),
    );
  }
}

class _VolunteerCard extends StatelessWidget {
  final VolunteerModel volunteer;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  const _VolunteerCard({required this.volunteer, this.onApprove, this.onReject});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = volunteer.status == 'approved' ? AppColors.green
        : volunteer.status == 'rejected' ? AppColors.red
        : AppColors.amber;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? AppColors.borderDark : AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.volunteer_activism, color: statusColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(volunteer.junction, style: TextStyle(color: isDark ? AppColors.textPrimary : AppColors.textPrimaryDark, fontSize: 13, fontWeight: FontWeight.w600)),
                    if (volunteer.citizenId != null && volunteer.citizenId!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Citizen: ${volunteer.citizenId}',
                        style: TextStyle(color: isDark ? AppColors.textSecondary : AppColors.textSecondaryDark, fontSize: 10),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 3),
                    Text(
                      '${volunteer.date?.split("T")[0] ?? ""} · ${volunteer.startTime ?? ""}–${volunteer.endTime ?? ""}',
                      style: TextStyle(color: isDark ? AppColors.textSecondary : AppColors.textSecondaryDark, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(volunteer.status.toUpperCase(), style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          if (onApprove != null || onReject != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: OutlinedButton(
                  onPressed: onReject,
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.red, side: const BorderSide(color: AppColors.red), padding: const EdgeInsets.symmetric(vertical: 8)),
                  child: const Text('Reject', style: TextStyle(fontSize: 12)),
                )),
                const SizedBox(width: 8),
                Expanded(child: ElevatedButton(
                  onPressed: onApprove,
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 8)),
                  child: const Text('Approve', style: TextStyle(fontSize: 12)),
                )),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

