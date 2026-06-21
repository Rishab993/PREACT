import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';
import '../../core/utils/complaint_image_url.dart';

/// Displays a complaint evidence image, resolving storage paths to loadable URLs.
class ComplaintImage extends StatefulWidget {
  final String? imagePath;
  final String? complaintId;
  final double height;
  final BoxFit fit;

  const ComplaintImage({
    super.key,
    required this.imagePath,
    this.complaintId,
    this.height = 120,
    this.fit = BoxFit.cover,
  });

  @override
  State<ComplaintImage> createState() => _ComplaintImageState();
}

class _ComplaintImageState extends State<ComplaintImage> {
  List<String> _candidates = [];
  int _candidateIndex = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCandidates();
  }

  @override
  void didUpdateWidget(covariant ComplaintImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath ||
        oldWidget.complaintId != widget.complaintId) {
      _candidateIndex = 0;
      _loadCandidates();
    }
  }

  Future<void> _loadCandidates() async {
    setState(() => _loading = true);
    final urls = await ComplaintImageUrl.resolveAll(
      widget.imagePath,
      complaintId: widget.complaintId,
    );
    debugPrint(
      '[ComplaintImage] model imagePath=${widget.imagePath} '
      'complaintId=${widget.complaintId} finalUrl=${urls.isNotEmpty ? urls.first : null}',
    );
    if (mounted) {
      setState(() {
        _candidates = urls;
        _candidateIndex = 0;
        _loading = false;
      });
    }
  }

  void _tryNextCandidate() {
    if (_candidateIndex + 1 >= _candidates.length) return;
    setState(() {
      _candidateIndex++;
      debugPrint(
        '[ComplaintImage] retry url=${_candidates[_candidateIndex]} '
        '(index $_candidateIndex/${_candidates.length})',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if ((widget.imagePath == null || widget.imagePath!.isEmpty) &&
        (widget.complaintId == null || widget.complaintId!.isEmpty)) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading) {
      return _loadingBox(isDark);
    }

    if (_candidates.isEmpty) {
      return const SizedBox.shrink();
    }

    final url = _candidates[_candidateIndex];

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        key: ValueKey(url),
        imageUrl: url,
        fit: widget.fit,
        width: double.infinity,
        height: widget.height,
        placeholder: (context, _) => _loadingBox(isDark),
        errorWidget: (context, _, error) {
          debugPrint('[ComplaintImage] load failed url=$url error=$error');
          if (_candidateIndex + 1 < _candidates.length) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _tryNextCandidate());
            return _loadingBox(isDark);
          }
          return Container(
            height: widget.height,
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
            child: const Center(
              child: Icon(Icons.broken_image_outlined, color: AppColors.textMuted, size: 24),
            ),
          );
        },
      ),
    );
  }

  Widget _loadingBox(bool isDark) {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: isDark ? AppColors.borderDark : AppColors.borderLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2563EB)),
        ),
      ),
    );
  }
}
