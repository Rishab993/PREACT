import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/colors.dart';
import '../../core/api/endpoints.dart';
import '../../core/api/api_client.dart';
import '../../providers/data_providers.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/skeleton_loader.dart';

class GroundTruthScreen extends ConsumerStatefulWidget {
  const GroundTruthScreen({super.key});

  @override
  ConsumerState<GroundTruthScreen> createState() => _GroundTruthScreenState();
}

class _GroundTruthScreenState extends ConsumerState<GroundTruthScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  String? _selectedEventId;
  final Map<String, double> _junctionStress = {};
  final Set<String> _selectedBottlenecks = {};
  final _notesCtrl = TextEditingController();
  int _officersActual = 5;
  bool _planFollowed = false;
  bool _isSubmitting = false;
  bool _submitted = false;
  late AnimationController _successCtrl;
  late Animation<double> _successAnim;

  @override
  void initState() {
    super.initState();
    for (final j in AppConstants.junctions.take(6)) {
      _junctionStress[j['name'] as String] = 0.5;
    }
    _successCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _successAnim = CurvedAnimation(parent: _successCtrl, curve: Curves.elasticOut);
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _successCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _selectedEventId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an event'), backgroundColor: AppColors.amber),
      );
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await ApiClient.instance.post(AppEndpoints.groundTruth, data: {
        'event_id': _selectedEventId,
        'junction_stress': _junctionStress,
        'bottlenecks': _selectedBottlenecks.toList(),
        'officers_actual': _officersActual,
        'plan_followed': _planFollowed,
        'notes': _notesCtrl.text,
      });
    } catch (_) {}
    setState(() { _isSubmitting = false; _submitted = true; });
    _successCtrl.forward();
  }

  @override
  Widget build(BuildContext context) {
    if (_submitted) return _buildSuccess();
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ground Truth Capture', style: Theme.of(context).textTheme.displayLarge),
              const Text('Post-event debrief — add actual observations', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 20),
              _buildEventPicker(),
              const SizedBox(height: 20),
              _buildJunctionStressSection(),
              const SizedBox(height: 20),
              _buildBottleneckSection(),
              const SizedBox(height: 20),
              _buildOtherFields(),
              const SizedBox(height: 20),
              _buildNotesField(),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: AppColors.backgroundDark,
                  ),
                  child: _isSubmitting
                      ? const CircularProgressIndicator(strokeWidth: 2, color: AppColors.backgroundDark)
                      : const Text('Submit Ground Truth', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEventPicker() => ref.watch(eventsProvider).when(
    loading: () => const SkeletonLoader(height: 52),
    error: (_, __) => const SizedBox(),
    data: (events) => DropdownButtonFormField<String>(
      value: _selectedEventId,
      decoration: InputDecoration(
        labelText: 'Select completed event',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dropdownColor: AppColors.surfaceElevatedDark,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
      items: events.map((e) => DropdownMenuItem(
        value: e.id,
        child: Text(e.name, overflow: TextOverflow.ellipsis),
      )).toList(),
      onChanged: (id) => setState(() => _selectedEventId = id),
    ),
  );

  Widget _buildJunctionStressSection() => GlassCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Junction Stress Levels', style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
        const Text('Rate how stressed each junction was', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        const SizedBox(height: 12),
        ..._junctionStress.entries.map((entry) {
          final label = entry.value < 0.4 ? 'Normal' : entry.value < 0.7 ? 'Moderate' : 'Severe';
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.key.split(' ').take(2).join(' '),
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      label.toUpperCase(),
                      style: TextStyle(
                        color: AppColors.fromSeverity(entry.value),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(entry.value * 100).toInt()}%',
                      style: TextStyle(color: AppColors.fromSeverity(entry.value), fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                Slider(
                  value: entry.value,
                  onChanged: (v) => setState(() => _junctionStress[entry.key] = v),
                  activeColor: AppColors.fromSeverity(entry.value),
                ),
              ],
            ),
          );
        }),
      ],
    ),
  );

  Widget _buildBottleneckSection() => GlassCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Bottleneck Causes', style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
        const Text('Select all that apply', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: List.generate(AppConstants.bottleneckOptions.length, (i) {
            final key = AppConstants.bottleneckOptions[i];
            final label = AppConstants.bottleneckLabels[i];
            final selected = _selectedBottlenecks.contains(key);
            return FilterChip(
              label: Text(label),
              selected: selected,
              onSelected: (v) => setState(() {
                if (v) _selectedBottlenecks.add(key);
                else _selectedBottlenecks.remove(key);
              }),
              selectedColor: const Color(0xFF2563EB).withOpacity(0.2),
              checkmarkColor: const Color(0xFF2563EB),
              labelStyle: TextStyle(
                color: selected ? const Color(0xFF2563EB) : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
              side: BorderSide(color: selected ? const Color(0xFF2563EB).withOpacity(0.5) : AppColors.borderDark),
            );
          }),
        ),
      ],
    ),
  );

  Widget _buildOtherFields() => GlassCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Deployment Details', style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        // Actual officers
        const Text('Actual officers deployed', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: _officersActual.toDouble(),
                min: 0, max: 30, divisions: 30,
                label: '$_officersActual',
                onChanged: (v) => setState(() => _officersActual = v.toInt()),
              ),
            ),
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: const Color(0xFF2563EB).withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
              child: Center(child: Text('$_officersActual', style: const TextStyle(color: const Color(0xFF2563EB), fontWeight: FontWeight.w700))),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Plan followed
        Row(
          children: [
            const Expanded(child: Text('PREACT plan was followed', style: TextStyle(color: AppColors.textSecondary, fontSize: 12))),
            Switch(
              value: _planFollowed,
              onChanged: (v) => setState(() => _planFollowed = v),
            ),
            Text(_planFollowed ? 'YES' : 'NO', style: TextStyle(color: _planFollowed ? AppColors.green : AppColors.red, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    ),
  );

  Widget _buildNotesField() => TextFormField(
    controller: _notesCtrl,
    style: const TextStyle(color: AppColors.textPrimary),
    maxLines: 4,
    decoration: InputDecoration(
      labelText: 'Observations & notes',
      hintText: 'e.g. Gate 2 was understaffed. Media vans blocked Route A...',
      alignLabelWithHint: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );

  Widget _buildSuccess() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: ScaleTransition(
          scale: _successAnim,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  color: AppColors.green.withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.green.withOpacity(0.5), width: 2),
                  boxShadow: [BoxShadow(color: AppColors.green.withOpacity(0.3), blurRadius: 24)],
                ),
                child: const Icon(Icons.check_rounded, color: AppColors.green, size: 48),
              ),
              const SizedBox(height: 24),
              const Text('Ground Truth Submitted', style: TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w700, fontFamily: 'SpaceGrotesk')),
              const SizedBox(height: 8),
              const Text('Data will improve future PREACT predictions', style: TextStyle(color: AppColors.textSecondary, fontSize: 14), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: () => setState(() { _submitted = false; _successCtrl.reset(); }),
                child: const Text('Submit Another'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

