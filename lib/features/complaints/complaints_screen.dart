import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/theme/colors.dart';
import '../../core/api/endpoints.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/supabase_service.dart';
import '../../providers/data_providers.dart';
import '../../providers/app_providers.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/skeleton_loader.dart';
import '../../shared/widgets/complaint_image.dart';

class ComplaintsScreen extends ConsumerStatefulWidget {
  const ComplaintsScreen({super.key});

  @override
  ConsumerState<ComplaintsScreen> createState() => _ComplaintsScreenState();
}

class _ComplaintsScreenState extends ConsumerState<ComplaintsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  String? _filterZone;
  String? _filterType;
  double _minConfidence = 0.0;

  // Citizen Raise Complaint Form State
  final _citizenFormKey = GlobalKey<FormState>();
  String _violationType = AppConstants.violationTypes.first;
  String _selectedZone = AppConstants.zones.first;
  final _descCtrl = TextEditingController();
  XFile? _selectedImage;
  Uint8List? _selectedImageBytes;
  bool _isSubmitting = false;

  Future<void> _pickImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (image == null) return;

      final ext = image.name.split('.').last.toLowerCase();
      final allowed = ['jpg', 'jpeg', 'png', 'webp'];
      if (!allowed.contains(ext)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Invalid format: $ext. Please select JPG, JPEG, PNG, or WEBP.'),
              backgroundColor: AppColors.red,
            ),
          );
        }
        return;
      }

      final bytes = await image.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('File too large. Maximum size is 5MB.'),
              backgroundColor: AppColors.red,
            ),
          );
        }
        return;
      }

      setState(() {
        _selectedImage = image;
        _selectedImageBytes = bytes;
      });
    } catch (e) {
      debugPrint('[ComplaintsScreen] Error picking image: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }



  List<ComplaintModel> _filtered(List<ComplaintModel> allComplaints, String status) {
    var list = allComplaints.where((c) {
      if (status == 'pending') return c.status == 'pending';
      if (status == 'valid') return c.status == 'valid';
      if (status == 'invalid') return c.status == 'invalid';
      return true; // all
    }).toList();
    if (_filterZone != null) list = list.where((c) => c.zone == _filterZone).toList();
    if (_filterType != null) list = list.where((c) => c.violationType == _filterType).toList();
    list = list.where((c) => c.confidenceScore >= _minConfidence).toList();
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(roleProvider);
    if (role == AppRole.citizen) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: _buildCitizenForm(),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ref.watch(complaintsProvider).when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: SkeletonList(count: 5),
            ),
            error: (err, stack) => ref.watch(complaintsListProvider).when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(16),
                    child: SkeletonList(count: 5),
                  ),
                  error: (_, __) => const Center(
                    child: Text(
                      'Could not load complaints',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  ),
                  data: (complaints) => _buildPoliceLayout(complaints),
                ),
            data: (complaints) => _buildPoliceLayout(complaints),
          ),
    );
  }

  Widget _buildPoliceLayout(List<ComplaintModel> complaints) {
    return Column(
      children: [
        _buildHeader(context),
        _buildFilterBar(),
        _buildTabBar(complaints),
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              _buildKanbanColumn(complaints, 'pending', 'Pending'),
              _buildKanbanColumn(complaints, 'valid', 'Valid'),
              _buildKanbanColumn(complaints, 'invalid', 'Rejected'),
              _buildKanbanColumn(complaints, 'all', 'All'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Citizen Complaints', style: Theme.of(context).textTheme.displayLarge),
              const Text('Validation queue', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ],
          ),
        ),
        IconButton(
          onPressed: () {
            ref.invalidate(complaintsProvider);
            ref.invalidate(complaintsListProvider);
          },
          icon: const Icon(Icons.refresh_outlined, color: Color(0xFF2563EB)),
        ),
      ],
    ),
  );

  Widget _buildFilterBar() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Row(
      children: [
        _FilterChip(
          label: _filterZone ?? 'All Zones',
          icon: Icons.location_on_outlined,
          onTap: () => _showZonePicker(),
          active: _filterZone != null,
        ),
        const SizedBox(width: 8),
        _FilterChip(
          label: _filterType ?? 'All Types',
          icon: Icons.category_outlined,
          onTap: () => _showTypePicker(),
          active: _filterType != null,
        ),
        const SizedBox(width: 8),
        _FilterChip(
          label: 'Score ≥ ${(_minConfidence * 100).toInt()}%',
          icon: Icons.bar_chart_outlined,
          onTap: () => _showConfidenceSlider(),
          active: _minConfidence > 0,
        ),
        if (_filterZone != null || _filterType != null || _minConfidence > 0) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => setState(() {
              _filterZone = null;
              _filterType = null;
              _minConfidence = 0;
            }),
            child: const Text('Clear', style: TextStyle(color: Color(0xFF2563EB), fontSize: 12)),
          ),
        ],
      ],
    ),
  );

  Widget _buildTabBar(List<ComplaintModel> allComplaints) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceElevatedDark : AppColors.surfaceElevatedLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: TabBar(
        controller: _tabCtrl,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        indicator: BoxDecoration(
          color: const Color(0xFF2563EB).withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF2563EB).withOpacity(0.4)),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: const Color(0xFF2563EB),
        unselectedLabelColor: isDark ? AppColors.textSecondary : AppColors.textSecondaryDark,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        tabs: [
          Tab(text: 'Pending (${_filtered(allComplaints, "pending").length})'),
          Tab(text: 'Valid (${_filtered(allComplaints, "valid").length})'),
          Tab(text: 'Rejected (${_filtered(allComplaints, "invalid").length})'),
          Tab(text: 'All'),
        ],
      ),
    );
  }

  Widget _buildKanbanColumn(List<ComplaintModel> allComplaints, String status, String title) {
    final items = _filtered(allComplaints, status);
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inbox_outlined, color: AppColors.textMuted, size: 48),
            const SizedBox(height: 12),
            Text('No $title complaints', style: const TextStyle(color: AppColors.textMuted)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (_, i) => _ComplaintCard(
        complaint: items[i],
        onTap: () => _showComplaintDetail(items[i]),
        onApprove: status == 'pending' ? () => _updateStatus(items[i], 'valid') : null,
        onReject: status == 'pending' ? () => _updateStatus(items[i], 'invalid') : null,
      ),
    );
  }

  Future<void> _updateStatus(ComplaintModel c, String status) async {
    // Update local cache FIRST — prevents the local 'pending' entry from
    // overriding the new status the next time the stream merges.
    await SupabaseService.updateLocalComplaintStatus(c.id, status);

    try {
      await ApiClient.instance.patch(
        '${AppEndpoints.complaints}/${c.id}',
        data: {'status': status},
      );
    } catch (_) {}

    ref.invalidate(complaintsProvider);
    ref.invalidate(complaintsListProvider);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'valid'
                ? 'Complaint approved and moved to Valid tab.'
                : 'Complaint rejected and moved to Rejected tab.',
          ),
          backgroundColor: status == 'valid' ? AppColors.green : AppColors.red,
        ),
      );
    }
  }

  void _showComplaintDetail(ComplaintModel c) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final formattedDate = c.submittedAt != null
        ? '${c.submittedAt!.day.toString().padLeft(2, '0')}/${c.submittedAt!.month.toString().padLeft(2, '0')}/${c.submittedAt!.year} ${c.submittedAt!.hour.toString().padLeft(2, '0')}:${c.submittedAt!.minute.toString().padLeft(2, '0')}'
        : 'Unknown';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (_, ctrl) => SingleChildScrollView(
          controller: ctrl,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: isDark ? AppColors.borderDark : AppColors.borderLight, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      c.title ?? AppConstants.violationTypeLabel(c.violationType ?? '') ?? 'Complaint Details',
                      style: TextStyle(color: isDark ? AppColors.textPrimary : AppColors.textPrimaryDark, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (c.isVolunteer)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: AppColors.amber.withOpacity(0.2), borderRadius: BorderRadius.circular(6)),
                      child: const Text('VOL', style: TextStyle(color: AppColors.amber, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'ID: ${c.id}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontFamily: 'monospace'),
              ),
              const SizedBox(height: 16),
              
              if ((c.imagePath != null && c.imagePath!.isNotEmpty) || c.id.isNotEmpty) ...[
                ComplaintImage(imagePath: c.imagePath, complaintId: c.id, height: 180),
                const SizedBox(height: 16),
              ],

              if (c.description != null && c.description!.isNotEmpty) ...[
                Text('Description', style: TextStyle(color: isDark ? AppColors.textSecondary : AppColors.textSecondaryDark, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(c.description!, style: TextStyle(color: isDark ? AppColors.textPrimary : AppColors.textPrimaryDark, fontSize: 14)),
                const SizedBox(height: 16),
              ],

              _detailRowThemed(Icons.category_outlined, 'Violation Type', AppConstants.violationTypeLabel(c.violationType ?? 'Unknown'), isDark),
              _detailRowThemed(Icons.location_on_outlined, 'GPS Location', '${c.lat?.toStringAsFixed(6)}, ${c.lng?.toStringAsFixed(6)}', isDark),
              _detailRowThemed(Icons.location_city_outlined, 'Zone', c.zone ?? 'Unknown', isDark),
              _detailRowThemed(Icons.calendar_today_outlined, 'Submitted At', formattedDate, isDark),
              _detailRowThemed(Icons.info_outline, 'Status', c.statusDisplay, isDark),
              _detailRowThemed(Icons.analytics_outlined, 'Confidence Score',
                  '${(c.confidenceScore * 100).toStringAsFixed(0)}%', isDark),

              const SizedBox(height: 16),
              Text('Severity Score', style: TextStyle(color: isDark ? AppColors.textSecondary : AppColors.textSecondaryDark, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: c.severity ?? 0.5,
                  backgroundColor: isDark ? AppColors.borderDark : AppColors.borderLight,
                  valueColor: AlwaysStoppedAnimation(AppColors.fromSeverity(c.severity ?? 0.5)),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 4),
              Text('${((c.severity ?? 0.5) * 100).toStringAsFixed(0)}% severity',
                  style: TextStyle(color: AppColors.fromSeverity(c.severity ?? 0.5), fontSize: 12, fontWeight: FontWeight.w600)),

              const SizedBox(height: 20),
              Text('Validation Pipeline', style: TextStyle(color: isDark ? AppColors.textSecondary : AppColors.textSecondaryDark, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _stepperItemThemed(1, 'GPS Plausibility Check', true, isDark),
              _stepperItemThemed(2, 'Image Blur Detection', c.confidenceScore > 0.4, isDark),
              _stepperItemThemed(3, 'Duplicate Suppression', true, isDark),
              _stepperItemThemed(4, 'Final Validation', c.status == 'valid', isDark),
              const SizedBox(height: 20),
              
              if (c.rejectionReason != null && c.rejectionReason!.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.red.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: AppColors.red, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(c.rejectionReason!, style: const TextStyle(color: AppColors.red, fontSize: 12))),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
  Widget _detailRowThemed(IconData icon, String label, String value, bool isDark) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Icon(icon, size: 14, color: isDark ? AppColors.textSecondary : AppColors.textSecondaryDark),
        const SizedBox(width: 6),
        Text('$label: ', style: TextStyle(color: isDark ? AppColors.textSecondary : AppColors.textSecondaryDark, fontSize: 12)),
        Expanded(child: Text(value, style: TextStyle(color: isDark ? AppColors.textPrimary : AppColors.textPrimaryDark, fontSize: 12))),
      ],
    ),
  );

  Widget _stepperItemThemed(int step, String label, bool done, bool isDark) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Container(
          width: 24, height: 24,
          decoration: BoxDecoration(
            color: done ? AppColors.green.withOpacity(0.15) : (isDark ? AppColors.borderDark : AppColors.borderLight),
            shape: BoxShape.circle,
            border: Border.all(color: done ? AppColors.green : (isDark ? AppColors.borderDark : AppColors.borderLight)),
          ),
          child: Center(
            child: done
                ? const Icon(Icons.check, size: 12, color: AppColors.green)
                : Text('$step', style: TextStyle(color: isDark ? AppColors.textMuted : AppColors.textSecondaryDark, fontSize: 10)),
          ),
        ),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: done ? (isDark ? AppColors.textPrimary : AppColors.textPrimaryDark) : (isDark ? AppColors.textMuted : AppColors.textSecondaryDark), fontSize: 13)),
      ],
    ),
  );

  void _showZonePicker() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          ListTile(
            title: Text('All Zones', style: TextStyle(color: isDark ? AppColors.textPrimary : AppColors.textPrimaryDark)),
            onTap: () { setState(() => _filterZone = null); Navigator.pop(context); },
          ),
          ...AppConstants.zones.map((z) => ListTile(
            title: Text(z, style: TextStyle(color: isDark ? AppColors.textPrimary : AppColors.textPrimaryDark)),
            trailing: _filterZone == z ? const Icon(Icons.check, color: Color(0xFF2563EB)) : null,
            onTap: () { setState(() => _filterZone = z); Navigator.pop(context); },
          )),
        ],
      ),
    );
  }

  void _showTypePicker() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          ListTile(
            title: Text('All Types', style: TextStyle(color: isDark ? AppColors.textPrimary : AppColors.textPrimaryDark)),
            onTap: () { setState(() => _filterType = null); Navigator.pop(context); },
          ),
          ...AppConstants.violationTypes.map((t) => ListTile(
            title: Text(AppConstants.violationTypeLabel(t), style: TextStyle(color: isDark ? AppColors.textPrimary : AppColors.textPrimaryDark)),
            onTap: () { setState(() => _filterType = t); Navigator.pop(context); },
          )),
        ],
      ),
    );
  }

  void _showConfidenceSlider() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Min Confidence Score'),
        content: StatefulBuilder(
          builder: (_, ss) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Slider(
                value: _minConfidence,
                onChanged: (v) { ss(() => _minConfidence = v); setState(() {}); },
                divisions: 10,
                label: '${(_minConfidence * 100).toInt()}%',
              ),
              Text('${(_minConfidence * 100).toInt()}%',
                  style: const TextStyle(color: Color(0xFF2563EB), fontSize: 24, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
      ),
    );
  }

  Widget _buildCitizenForm() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Card(
            color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: isDark ? AppColors.borderDark : AppColors.borderLight),
            ),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Form(
                key: _citizenFormKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Raise a Traffic Complaint',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Report incidents to Bengaluru Traffic Police.',
                      style: TextStyle(
                        color: isDark ? AppColors.textSecondary : AppColors.textSecondaryDark,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 32),

                    DropdownButtonFormField<String>(
                      value: _violationType,
                      decoration: const InputDecoration(labelText: 'Incident Type *'),
                      dropdownColor: isDark ? AppColors.surfaceElevatedDark : AppColors.surfaceElevatedLight,
                      style: TextStyle(color: isDark ? AppColors.textPrimary : AppColors.textPrimaryDark),
                      items: AppConstants.violationTypes
                          .map((t) => DropdownMenuItem(value: t, child: Text(AppConstants.violationTypeLabel(t))))
                          .toList(),
                      onChanged: (v) => setState(() => _violationType = v!),
                    ),
                    const SizedBox(height: 20),

                    DropdownButtonFormField<String>(
                      value: _selectedZone,
                      decoration: const InputDecoration(labelText: 'Zone *'),
                      dropdownColor: isDark ? AppColors.surfaceElevatedDark : AppColors.surfaceElevatedLight,
                      style: TextStyle(color: isDark ? AppColors.textPrimary : AppColors.textPrimaryDark),
                      items: AppConstants.zones
                          .map((z) => DropdownMenuItem(value: z, child: Text(z)))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedZone = v!),
                    ),
                    const SizedBox(height: 20),

                    TextFormField(
                      controller: _descCtrl,
                      style: TextStyle(color: isDark ? AppColors.textPrimary : AppColors.textPrimaryDark),
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Description *',
                        hintText: 'Describe the incident...',
                        alignLabelWithHint: true,
                      ),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Description required' : null,
                    ),
                    const SizedBox(height: 28),

                    // Real Image Upload button with preview
                    if (_selectedImageBytes != null) ...[
                      Center(
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          constraints: const BoxConstraints(maxHeight: 180),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: isDark ? AppColors.borderDark : AppColors.borderLight),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.memory(
                              _selectedImageBytes!,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickImage,
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: Text(_selectedImage?.name ?? 'Upload Photo Evidence *'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF2563EB),
                              side: BorderSide(color: const Color(0xFF2563EB).withOpacity(0.5)),
                            ),
                          ),
                        ),
                        if (_selectedImage != null) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.clear, color: AppColors.red),
                            onPressed: () => setState(() {
                              _selectedImage = null;
                              _selectedImageBytes = null;
                            }),
                          ),
                        ]
                      ],
                    ),
                    const SizedBox(height: 32),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submitCitizenComplaint,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                        ),
                        child: _isSubmitting
                            ? const CircularProgressIndicator(strokeWidth: 2, color: Colors.white)
                            : const Text('Submit Complaint', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submitCitizenComplaint() async {
    if (!_citizenFormKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    if (_selectedImageBytes == null || _selectedImage == null) {
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Photo upload is required.'),
          backgroundColor: AppColors.red,
        ),
      );
      return;
    }

    final junction = AppConstants.junctions.first;
    final lat = junction['lat'] as double;
    final lng = junction['lng'] as double;

    try {
      final formData = FormData.fromMap({
        'violation_type': _violationType,
        'lat': lat,
        'lng': lng,
        'zone': _selectedZone,
        'description': _descCtrl.text,
        'image': MultipartFile.fromBytes(
          _selectedImageBytes!,
          filename: _selectedImage!.name,
        ),
      });

      final response = await ApiClient.instance.post(AppEndpoints.complaints, data: formData);
      final data = response.data is Map<String, dynamic>
          ? response.data as Map<String, dynamic>
          : <String, dynamic>{};

      final complaintId = _extractComplaintId(data);
      final confidence = _extractConfidenceScore(data) ?? 0.0;
      final backendStatus = _extractStatus(data) ?? 'pending';
      final reason = data['reason']?.toString() ?? 'Submitted for review';
      var storedImagePath = _extractImagePath(data);

      if (complaintId != null) {
        final remoteImagePath =
            await SupabaseService.instance.fetchComplaintImagePath(complaintId);
        storedImagePath = remoteImagePath ?? storedImagePath;
      }

      final newComplaint = {
        'id': complaintId ?? 'comp-${DateTime.now().millisecondsSinceEpoch}',
        'violation_type': _violationType,
        'description': _descCtrl.text,
        'lat': lat,
        'lng': lng,
        if (storedImagePath != null && storedImagePath.isNotEmpty)
          'image_path': storedImagePath,
        'status': backendStatus,
        'confidence_score': confidence,
        if (reason.isNotEmpty) 'rejection_reason': reason,
        'is_volunteer': false,
        'zone': _selectedZone,
        'submitted_at': DateTime.now().toIso8601String(),
      };
      await SupabaseService.saveLocalComplaint(newComplaint);

      setState(() {
        _isSubmitting = false;
        _descCtrl.clear();
        _selectedImage = null;
        _selectedImageBytes = null;
      });

      ref.invalidate(complaintsProvider);
      ref.invalidate(complaintsListProvider);

      if (mounted) {
        final isDuplicate = data['is_duplicate'] as bool? ?? data['duplicate'] as bool? ?? false;
        _showSubmissionResult(
          status: backendStatus,
          reason: reason,
          complaintId: complaintId ?? newComplaint['id']!.toString(),
          confidenceScore: confidence,
          isDuplicate: isDuplicate,
        );
      }
    } catch (e) {
      debugPrint('[ComplaintsScreen] Submit error: $e');
      setState(() => _isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit: ${e.toString()}'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
  }

  void _showSubmissionResult({
    required String status,
    required String reason,
    required String complaintId,
    required double confidenceScore,
    bool isDuplicate = false,
  }) {
    final isRejected = status == 'invalid' || status == 'rejected';
    final scoreColor = confidenceScore >= 0.7
        ? AppColors.green
        : confidenceScore >= 0.4
            ? AppColors.amber
            : AppColors.red;
    final shortId = complaintId.length > 8 ? '${complaintId.substring(0, 8)}...' : complaintId;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            Icon(
              isRejected ? Icons.warning_amber_outlined : Icons.check_circle_outline,
              color: isRejected ? AppColors.red : AppColors.green,
              size: 22,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Complaint Submitted',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _resultRow('Complaint ID', shortId),
            _resultRow('Status', status),
            const SizedBox(height: 6),
            Row(
              children: [
                SizedBox(
                  width: 120,
                  child: Text('Confidence', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                ),
                Text(
                  '${(confidenceScore * 100).toStringAsFixed(0)}%',
                  style: TextStyle(color: scoreColor, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: confidenceScore.clamp(0.0, 1.0),
                backgroundColor: Colors.grey.withOpacity(0.2),
                valueColor: AlwaysStoppedAnimation(scoreColor),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 8),
            if (isDuplicate)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.amber.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.amber.withOpacity(0.4)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.copy_outlined, color: AppColors.amber, size: 14),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Similar complaint already reported nearby',
                        style: TextStyle(color: AppColors.amber, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            _resultRow('Reason', reason.isEmpty ? 'Submitted for police review' : reason),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
        ],
      ),
    );
  }

  Widget _resultRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );

  String? _extractComplaintId(dynamic responseData) {
    if (responseData == null) return null;
    if (responseData is Map<String, dynamic>) {
      for (final key in ['complaint_id', 'id']) {
        final value = responseData[key]?.toString();
        if (value != null && value.isNotEmpty) return value;
      }
      for (final key in ['data', 'complaint', 'result']) {
        final nested = responseData[key];
        if (nested is Map<String, dynamic>) {
          final nestedId = _extractComplaintId(nested);
          if (nestedId != null) return nestedId;
        }
      }
    }
    return null;
  }

  double? _extractConfidenceScore(dynamic responseData) {
    if (responseData is Map<String, dynamic>) {
      final direct = responseData['confidence_score'];
      if (direct is num) return direct.toDouble();
      for (final key in ['data', 'complaint', 'result']) {
        final nested = responseData[key];
        if (nested is Map<String, dynamic>) {
          final nestedScore = nested['confidence_score'];
          if (nestedScore is num) return nestedScore.toDouble();
        }
      }
    }
    return null;
  }

  String? _extractStatus(dynamic responseData) {
    if (responseData is Map<String, dynamic>) {
      final direct = responseData['status']?.toString();
      if (direct != null && direct.isNotEmpty) return direct;
      for (final key in ['data', 'complaint', 'result']) {
        final nested = responseData[key];
        if (nested is Map<String, dynamic>) {
          final nestedStatus = _extractStatus(nested);
          if (nestedStatus != null) return nestedStatus;
        }
      }
    }
    return null;
  }

  String? _extractImagePath(dynamic responseData) {
    if (responseData == null) return null;
    if (responseData is Map<String, dynamic>) {
      final direct = ComplaintModel.readImagePath(responseData);
      if (direct != null) return direct;

      for (final key in ['data', 'complaint', 'result']) {
        final nested = responseData[key];
        if (nested is Map<String, dynamic>) {
          final nestedPath = ComplaintModel.readImagePath(nested);
          if (nestedPath != null) return nestedPath;
        }
      }
    }
    return null;
  }
}

// ── Violation-type → contextual icon mapping ─────────────────────────────────
IconData _iconForViolationType(String? type) {
  switch (type) {
    case 'vehicle_breakdown': return Icons.car_repair;
    case 'accident':          return Icons.car_crash;
    case 'pot_holes':         return Icons.warning_amber_rounded;
    case 'water_logging':     return Icons.water_damage;
    case 'tree_fall':         return Icons.park;
    case 'congestion':        return Icons.traffic;
    case 'road_conditions':   return Icons.construction;
    case 'others':            return Icons.report_problem;
    default:                  return Icons.report_outlined;
  }
}

class _ComplaintCard extends StatelessWidget {
  final ComplaintModel complaint;
  final VoidCallback onTap;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  const _ComplaintCard({
    required this.complaint,
    required this.onTap,
    this.onApprove,
    this.onReject,
  });

  Color get _statusColor {
    switch (complaint.status) {
      case 'valid': return AppColors.green;
      case 'invalid': return AppColors.red;
      default: return AppColors.amber;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: _statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_iconForViolationType(complaint.violationType), color: _statusColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              AppConstants.violationTypeLabel(complaint.violationType ?? 'other'),
                              style: TextStyle(
                                color: isDark ? AppColors.textPrimary : AppColors.textPrimaryDark,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (complaint.isVolunteer)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(color: AppColors.amber.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                              child: const Text('VOL', style: TextStyle(color: AppColors.amber, fontSize: 9, fontWeight: FontWeight.w700)),
                            ),
                        ],
                      ),
                      if (complaint.description != null && complaint.description!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          complaint.description!,
                          style: TextStyle(
                            color: isDark ? AppColors.textSecondary : AppColors.textSecondaryDark,
                            fontSize: 11,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 3),
                      Text(
                        'ID: ${complaint.id.length > 8 ? complaint.id.substring(0, 8) : complaint.id} · ${complaint.zone ?? "Unknown"} · ${complaint.timeAgo}',
                        style: TextStyle(
                          color: isDark ? AppColors.textMuted : AppColors.textSecondaryDark,
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if ((complaint.imagePath != null && complaint.imagePath!.isNotEmpty) ||
                complaint.id.isNotEmpty) ...[
              const SizedBox(height: 10),
              ComplaintImage(
                imagePath: complaint.imagePath,
                complaintId: complaint.id,
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: complaint.confidenceScore.clamp(0.0, 1.0),
                      backgroundColor: isDark ? AppColors.borderDark : AppColors.borderLight,
                      valueColor: AlwaysStoppedAnimation(
                        AppColors.fromSeverity(complaint.confidenceScore),
                      ),
                      minHeight: 4,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(complaint.confidenceScore * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: AppColors.fromSeverity(complaint.confidenceScore),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    complaint.statusDisplay,
                    style: TextStyle(color: _statusColor, fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            if (onApprove != null || onReject != null) ...
              [
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onReject,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.red,
                          side: const BorderSide(color: AppColors.red),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        child: const Text('Reject', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: onApprove,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        child: const Text('Approve', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ),
              ],
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  const _FilterChip({required this.label, required this.icon, required this.onTap, this.active = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF2563EB).withOpacity(0.12)
              : (isDark ? AppColors.surfaceElevatedDark : AppColors.surfaceElevatedLight),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: active
                  ? const Color(0xFF2563EB).withOpacity(0.5)
                  : (isDark ? AppColors.borderDark : AppColors.borderLight)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: active ? const Color(0xFF2563EB) : (isDark ? AppColors.textSecondary : AppColors.textSecondaryDark)),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: active ? const Color(0xFF2563EB) : (isDark ? AppColors.textSecondary : AppColors.textSecondaryDark), fontSize: 11, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
