import 'package:flutter/foundation.dart';
import '../api/endpoints.dart';
import '../config/app_config.dart';
import '../auth/supabase_service.dart';

/// Resolves a complaint image reference into one or more loadable URLs.
class ComplaintImageUrl {
  ComplaintImageUrl._();

  static const List<String> _storageBuckets = [
    'complaints',
    'complaint-images',
    'evidence',
  ];

  /// Builds ordered URL candidates for [imagePath] and optional [complaintId].
  static List<String> buildCandidates(String? imagePath, {String? complaintId}) {
    final urls = <String>[];

    void add(String? url) {
      if (url == null || url.isEmpty) return;
      if (!urls.contains(url)) urls.add(url);
    }

    final trimmed = imagePath?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
        add(trimmed);
      } else if (trimmed.startsWith('/storage/v1/object/')) {
        add('${AppConfig.supabaseUrl}$trimmed');
      } else if (trimmed.startsWith('/')) {
        add('${AppEndpoints.apiBase}$trimmed');
      } else {
        addAllPublicStorageUrls(trimmed, add);
        add('${AppEndpoints.apiBase}/uploads/$trimmed');
        add('${AppEndpoints.apiBase}/api/uploads/$trimmed');
      }
    }

    if (complaintId != null && complaintId.isNotEmpty) {
      add('${AppEndpoints.apiBase}/api/complaints/$complaintId/image');
      addAllPublicStorageUrls(complaintId, add);
      addAllPublicStorageUrls('$complaintId.jpg', add);
      addAllPublicStorageUrls('$complaintId/image.jpg', add);
      add('${AppEndpoints.apiBase}/uploads/$complaintId.jpg');
      add('${AppEndpoints.apiBase}/uploads/$complaintId.jpeg');
      add('${AppEndpoints.apiBase}/uploads/$complaintId.png');
    }

    return urls;
  }

  static void addAllPublicStorageUrls(String key, void Function(String?) add) {
    if (!SupabaseService.isInitialized) return;
    for (final bucket in _storageBuckets) {
      try {
        add(SupabaseService.instance.client.storage
            .from(bucket)
            .getPublicUrl(_normalizeStorageKey(key, bucket)));
      } catch (_) {}
    }
  }

  static String? resolveSync(String? imagePath, {String? complaintId}) {
    final candidates = buildCandidates(imagePath, complaintId: complaintId);
    return candidates.isEmpty ? null : candidates.first;
  }

  static Future<List<String>> resolveAll(String? imagePath, {String? complaintId}) async {
    final urls = buildCandidates(imagePath, complaintId: complaintId);
    final signed = await resolveSignedUrls(imagePath, complaintId: complaintId);
    for (final url in signed) {
      if (!urls.contains(url)) urls.insert(0, url);
    }
    debugPrint('[ComplaintImageUrl] imagePath=$imagePath complaintId=$complaintId candidates=$urls');
    return urls;
  }

  static Future<List<String>> resolveSignedUrls(
    String? imagePath, {
    String? complaintId,
  }) async {
    if (!SupabaseService.isInitialized) return [];

    final keys = <String>{};
    final trimmed = imagePath?.trim();
    if (trimmed != null && trimmed.isNotEmpty &&
        !trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      keys.addAll(_storageKeyCandidates(trimmed));
    }
    if (complaintId != null && complaintId.isNotEmpty) {
      keys.add(complaintId);
      keys.add('$complaintId.jpg');
      keys.add('$complaintId/image.jpg');
    }

    final signed = <String>[];
    for (final bucket in _storageBuckets) {
      final storage = SupabaseService.instance.client.storage.from(bucket);
      for (final key in keys) {
        try {
          final url = await storage.createSignedUrl(_normalizeStorageKey(key, bucket), 3600);
          if (!signed.contains(url)) signed.add(url);
        } catch (_) {}
      }
    }
    return signed;
  }

  static String _normalizeStorageKey(String path, String bucket) {
    final prefix = '$bucket/';
    if (path.startsWith(prefix)) {
      return path.substring(prefix.length);
    }
    return path;
  }

  static List<String> _storageKeyCandidates(String path) {
    final keys = <String>[path];
    if (!path.startsWith('uploads/')) {
      keys.add('uploads/$path');
    }
    return keys;
  }
}
