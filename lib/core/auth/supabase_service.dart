import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../../shared/models/models.dart';

class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  static bool _isInitialized = false;
  static bool get isInitialized => _isInitialized;

  static Future<void> initialize() async {
    // Attempt to check if already initialized (hot restarts or test environments)
    try {
      // ignore: unnecessary_statements
      Supabase.instance.client;
      _isInitialized = true;
      return;
    } catch (_) {}

    // Read exclusively from dotenv via AppConfig.
    // AppConfig.validate() in main() guarantees these are non-empty before
    // this method is called.
    String url = AppConfig.supabaseUrl;
    final String anonKey = AppConfig.supabaseAnonKey;

    // Remove trailing slash if present in URL
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    // Remove rest/v1 suffix if present
    if (url.endsWith('/rest/v1')) {
      url = url.substring(0, url.indexOf('/rest/v1'));
    } else if (url.endsWith('rest/v1')) {
      url = url.substring(0, url.indexOf('rest/v1'));
    }

    try {
      await Supabase.initialize(
        url: url,
        anonKey: anonKey,
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.implicit,
          localStorage: EmptyLocalStorage(),
        ),
        realtimeClientOptions: const RealtimeClientOptions(
          eventsPerSecond: 10,
        ),
      );
      _isInitialized = true;
      debugPrint('[Supabase] Initialized successfully with URL: $url');
    } catch (e) {
      debugPrint('[Supabase] Initialization error: $e. Using offline seed mode.');
      _isInitialized = false;
    }
  }

  SupabaseClient get client {
    if (!_isInitialized) {
      throw StateError('Supabase is not initialized');
    }
    return Supabase.instance.client;
  }

  // ── Local alerts cache ──────────────────────────────────────────────────
  static Future<void> saveLocalAlert(Map<String, dynamic> alert) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('local_alerts') ?? [];
      list.add(jsonEncode(alert));
      await prefs.setStringList('local_alerts', list);
    } catch (e) {
      debugPrint('[SupabaseService] saveLocalAlert error: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getLocalAlerts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('local_alerts') ?? [];
      return list.map((item) => jsonDecode(item) as Map<String, dynamic>).toList();
    } catch (e) {
      debugPrint('[SupabaseService] getLocalAlerts error: $e');
      return [];
    }
  }

  static Future<void> deleteLocalAlert(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('local_alerts') ?? [];
      final updatedList = list.where((item) {
        final Map<String, dynamic> alert = jsonDecode(item);
        return alert['id'] != id;
      }).toList();
      await prefs.setStringList('local_alerts', updatedList);
    } catch (e) {
      debugPrint('[SupabaseService] deleteLocalAlert error: $e');
    }
  }

  // ── Local complaints cache ──────────────────────────────────────────────
  static Future<void> saveLocalComplaint(Map<String, dynamic> complaint) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('local_complaints') ?? [];
      list.add(jsonEncode(complaint));
      await prefs.setStringList('local_complaints', list);
      debugPrint('[SupabaseService] saveLocalComplaint successful: $complaint');
    } catch (e) {
      debugPrint('[SupabaseService] saveLocalComplaint error: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getLocalComplaints() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('local_complaints') ?? [];
      return list.map((item) => jsonDecode(item) as Map<String, dynamic>).toList();
    } catch (e) {
      debugPrint('[SupabaseService] getLocalComplaints error: $e');
      return [];
    }
  }

  /// Updates the status field of a locally-cached complaint.
  /// Must be called after approve/reject so the local cache reflects the new
  /// status and does not continue to override the remote DB value.
  static Future<void> updateLocalComplaintStatus(String id, String status) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('local_complaints') ?? [];
      final updatedList = list.map((item) {
        final Map<String, dynamic> complaint = jsonDecode(item);
        if (complaint['id']?.toString() == id) {
          complaint['status'] = status;
          return jsonEncode(complaint);
        }
        return item;
      }).toList();
      await prefs.setStringList('local_complaints', updatedList);
      debugPrint('[SupabaseService] updateLocalComplaintStatus: $id -> $status');
    } catch (e) {
      debugPrint('[SupabaseService] updateLocalComplaintStatus error: $e');
    }
  }

  static List<Map<String, dynamic>> _mergeComplaints(
      List<Map<String, dynamic>> locals, List<Map<String, dynamic>> remote) {
    final Set<String> seenIds = {};
    final Set<String> seenTitles = {};
    final List<Map<String, dynamic>> result = [];
    
    for (final item in locals) {
      final id = item['id']?.toString() ?? '';
      final title = item['title']?.toString() ?? '';
      if (id.isNotEmpty) seenIds.add(id);
      if (title.isNotEmpty) seenTitles.add(title);
      result.add(Map<String, dynamic>.from(item));
    }
    
    for (final item in remote) {
      final id = item['id']?.toString() ?? '';
      final title = item['title']?.toString() ?? '';
      final remoteImage = ComplaintModel.readImagePath(item);

      if (seenIds.contains(id)) {
        _upgradeImagePath(result, id: id, remoteImage: remoteImage);
        continue;
      }

      if (title.isNotEmpty && seenTitles.contains(title)) {
        _upgradeImagePath(result, title: title, remoteImage: remoteImage);
        continue;
      }

      result.add(item);
      if (id.isNotEmpty) seenIds.add(id);
      if (title.isNotEmpty) seenTitles.add(title);
    }
    
    return result;
  }

  static void _upgradeImagePath(
    List<Map<String, dynamic>> result, {
    String? id,
    String? title,
    required String? remoteImage,
  }) {
    if (remoteImage == null || !ComplaintModel.isStrongImagePath(remoteImage)) return;

    for (var i = 0; i < result.length; i++) {
      final entry = result[i];
      final matchesId = id != null && entry['id']?.toString() == id;
      final matchesTitle = title != null && entry['title']?.toString() == title;
      if (!matchesId && !matchesTitle) continue;

      final localImage = ComplaintModel.readImagePath(entry);
      if (!ComplaintModel.isStrongImagePath(localImage)) {
        result[i] = {
          ...entry,
          'image_path': remoteImage,
        };
        debugPrint(
          '[SupabaseService] Upgraded image_path for ${id ?? title}: $remoteImage',
        );
      }
      break;
    }
  }

  /// Fetches the stored image reference for a complaint from Supabase.
  Future<String?> fetchComplaintImagePath(String complaintId) async {
    if (!_isInitialized) return null;
    try {
      final row = await client
          .from('complaints')
          .select('image_path, image_url')
          .eq('id', complaintId)
          .maybeSingle();
      if (row == null) return null;
      final imagePath = ComplaintModel.readImagePath(row);
      debugPrint(
        '[SupabaseService] fetchComplaintImagePath id=$complaintId imagePath=$imagePath raw=$row',
      );
      return imagePath;
    } catch (e) {
      debugPrint('[SupabaseService] fetchComplaintImagePath error: $e');
      return null;
    }
  }

  static List<Map<String, dynamic>> _mergeAlerts(
      List<Map<String, dynamic>> locals, List<Map<String, dynamic>> remote) {
    final Set<String> seenIds = {};
    final Set<String> seenMessages = {};
    final List<Map<String, dynamic>> result = [];
    
    for (final item in locals) {
      final id = item['id']?.toString() ?? '';
      final msg = item['message_en']?.toString() ?? '';
      if (id.isNotEmpty) seenIds.add(id);
      if (msg.isNotEmpty) seenMessages.add(msg);
      result.add(item);
    }
    
    for (final item in remote) {
      final id = item['id']?.toString() ?? '';
      final msg = item['message_en']?.toString() ?? '';
      
      if (seenIds.contains(id) || (msg.isNotEmpty && seenMessages.contains(msg))) {
        continue;
      }
      result.add(item);
    }
    
    return result;
  }

  Future<void> createAlert(Map<String, dynamic> alertData) async {
    final alertId = 'alert-${DateTime.now().millisecondsSinceEpoch}';
    final fullAlert = {
      'id': alertId,
      ...alertData,
      'created_at': DateTime.now().toIso8601String(),
    };
    
    debugPrint('[DEBUG] Alert payload before insert: $fullAlert');
    
    // Always save locally first to ensure instant view update
    await saveLocalAlert(fullAlert);
    
    if (_isInitialized) {
      try {
        final res = await client.from('alerts').insert(fullAlert).select();
        debugPrint('[DEBUG] Insert response: $res');
        return;
      } catch (e) {
        debugPrint('[SupabaseService] createAlert insert error: $e');
      }
    }
  }

  Future<void> deleteAlert(String id) async {
    if (id.startsWith('local-alert-') || id.startsWith('alert-')) {
      await deleteLocalAlert(id);
    }
    if (_isInitialized) {
      try {
        await client.from('alerts').delete().eq('id', id);
        return;
      } catch (e) {
        debugPrint('[SupabaseService] deleteAlert error: $e');
      }
    }
  }

  // ── Realtime streams ─────────────────────────────────────────────────────

  /// Stream of all active alerts (public, no auth required)
  Stream<List<Map<String, dynamic>>> alertsStream({String? zone}) {
    if (!_isInitialized) {
      return Stream.fromFuture(getLocalAlerts()).map((locals) {
        final list = _mergeAlerts(locals, _seedAlerts());
        if (zone != null) {
          return list.where((item) => item['zone'] == zone).toList();
        }
        return list;
      });
    }
    
    final controller = StreamController<List<Map<String, dynamic>>>();
    
    // Fetch initial list immediately
    fetchAlerts().then((initialAlerts) {
      if (!controller.isClosed) {
        debugPrint('[DEBUG] Stream initial fetch result count: ${initialAlerts.length}');
        controller.add(initialAlerts);
      }
    }).catchError((err) {
      debugPrint('[SupabaseService] Stream initial fetch error: $err');
    });

    try {
      final dbStream = client.from('alerts').stream(primaryKey: ['id'])
          .order('created_at', ascending: false)
          .asyncMap((supabaseRows) async {
            final locals = await getLocalAlerts();
            final merged = _mergeAlerts(locals, supabaseRows);
            debugPrint('[DEBUG] Stream realtime database update count: ${supabaseRows.length}, merged count: ${merged.length}');
            return merged;
          });
      
      final subscription = dbStream.listen(
        (data) {
          if (!controller.isClosed) {
            debugPrint('[DEBUG] Realtime event received: $data');
            controller.add(data);
          }
        },
        onError: (err) {
          debugPrint('[SupabaseService] Realtime alerts stream error: $err');
        },
      );
      
      controller.onCancel = () {
        subscription.cancel();
      };
    } catch (e) {
      debugPrint('[SupabaseService] Realtime alerts stream subscription error: $e');
    }

    return controller.stream.map((list) {
      if (zone != null) {
        return list.where((item) => item['zone'] == zone).toList();
      }
      return list;
    });
  }

  /// Stream of complaints for a zone (police use)
  Stream<List<Map<String, dynamic>>> complaintsStream({String? zone}) {
    if (!_isInitialized) {
      return Stream.fromFuture(getLocalComplaints()).map((locals) {
        final list = _mergeComplaints(locals, _seedComplaints());
        if (zone != null) {
          return list.where((item) => item['zone'] == zone).toList();
        }
        return list;
      });
    }
    var query = client.from('complaints').stream(primaryKey: ['id'])
        .order('submitted_at', ascending: false)
        .asyncMap((supabaseRows) async {
          final locals = await getLocalComplaints();
          final merged = _mergeComplaints(locals, supabaseRows);
          if (zone != null) {
            return merged.where((item) => item['zone'] == zone).toList();
          }
          return merged;
        });
    return query;
  }

  /// Stream of recent events
  Stream<List<Map<String, dynamic>>> eventsStream() {
    if (!_isInitialized) {
      return Stream.value(_seedEvents());
    }
    return client.from('events').stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(20);
  }

  // ── One-shot fetches ─────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchAlerts({int limit = 20}) async {
    final locals = await getLocalAlerts();
    if (!_isInitialized) {
      final list = _mergeAlerts(locals, _seedAlerts());
      debugPrint('[DEBUG] Query result count (fetchAlerts offline): ${list.length}');
      return list.take(limit).toList();
    }
    try {
      final response = await client
          .from('alerts')
          .select()
          .order('created_at', ascending: false)
          .limit(limit);
      final supabaseRows = List<Map<String, dynamic>>.from(response);
      final list = _mergeAlerts(locals, supabaseRows);
      debugPrint('[DEBUG] Query result count (fetchAlerts online): ${list.length}');
      return list.take(limit).toList();
    } catch (e) {
      debugPrint('[Supabase] fetchAlerts error: $e');
      final list = _mergeAlerts(locals, _seedAlerts());
      debugPrint('[DEBUG] Query result count (fetchAlerts error fallback): ${list.length}');
      return list.take(limit).toList();
    }
  }

  Future<List<Map<String, dynamic>>> fetchEvents({int limit = 20}) async {
    if (!_isInitialized) return [];
    try {
      final response = await client
          .from('events')
          .select()
          .order('created_at', ascending: false)
          .limit(limit);
      final list = List<Map<String, dynamic>>.from(response);
      return list;
    } catch (e) {
      debugPrint('[Supabase] fetchEvents error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchComplaints({
    String? status,
    String? zone,
    int limit = 50,
  }) async {
    final locals = await getLocalComplaints();
    if (!_isInitialized) {
      var data = _mergeComplaints(locals, _seedComplaints());
      if (status != null) data = data.where((r) => r['status'] == status).toList();
      if (zone != null) data = data.where((r) => r['zone'] == zone).toList();
      return data;
    }
    try {
      var query = client.from('complaints').select();
      if (status != null) query = query.eq('status', status);
      if (zone != null) query = query.eq('zone', zone);
      final response = await query.order('submitted_at', ascending: false).limit(limit);
      final supabaseRows = List<Map<String, dynamic>>.from(response);
      return _mergeComplaints(locals, supabaseRows);
    } catch (e) {
      debugPrint('[Supabase] fetchComplaints error: $e');
      var data = _mergeComplaints(locals, _seedComplaints());
      if (status != null) data = data.where((r) => r['status'] == status).toList();
      if (zone != null) data = data.where((r) => r['zone'] == zone).toList();
      return data;
    }
  }

  Future<List<Map<String, dynamic>>> fetchVolunteers({String? status}) async {
    if (!_isInitialized) {
      var data = _seedVolunteers();
      if (status != null) data = data.where((r) => r['status'] == status).toList();
      return data;
    }
    try {
      var query = client.from('volunteer_assignments').select();
      if (status != null) query = query.eq('status', status);
      final response = await query.order('created_at', ascending: false).limit(30);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('[Supabase] fetchVolunteers error: $e');
      return _seedVolunteers();
    }
  }

  Future<List<Map<String, dynamic>>> fetchForecasts({String? zone}) async {
    if (!_isInitialized) return [];
    try {
      var query = client.from('forecasts').select();
      if (zone != null) query = query.eq('zone', zone);
      final response = await query.order('forecast_hour').limit(72 * 10);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('[Supabase] fetchForecasts error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchDeployments({String? eventId}) async {
    if (!_isInitialized) return _seedDeployments();
    try {
      var query = client.from('deployments').select('*, officers(name, badge_number, zone)');
      if (eventId != null) query = query.eq('event_id', eventId);
      final response = await query.order('start_time').limit(50);
      final list = List<Map<String, dynamic>>.from(response);
      if (list.isEmpty) return _seedDeployments();
      return list;
    } catch (e) {
      debugPrint('[Supabase] fetchDeployments error: $e');
      return _seedDeployments();
    }
  }

  Future<List<Map<String, dynamic>>> fetchOfficers() async {
    if (!_isInitialized) return _seedOfficers();
    try {
      final response = await client.from('officers').select().order('name').limit(50);
      final list = List<Map<String, dynamic>>.from(response);
      if (list.isEmpty) return _seedOfficers();
      return list;
    } catch (e) {
      debugPrint('[Supabase] fetchOfficers error: $e');
      return _seedOfficers();
    }
  }

  Future<List<Map<String, dynamic>>> fetchSimulations({String? eventId}) async {
    if (!_isInitialized) return [];
    try {
      var query = client.from('simulations').select();
      if (eventId != null) query = query.eq('event_id', eventId);
      final response = await query.order('created_at', ascending: false).limit(10);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('[Supabase] fetchSimulations error: $e');
      return [];
    }
  }

  // ── Seed data fallbacks (never show blank screen) ─────────────────────────

  /// Public accessor so providers can inject seed data when Supabase returns
  /// an empty table (e.g., during a demo before any alerts are created).
  static List<AlertModel> seedAlertModels() =>
      _seedAlerts().map((r) => AlertModel.fromJson(r)).toList();

  static List<OfficerModel> seedOfficerModels() =>
      _seedOfficers().map((r) => OfficerModel.fromJson(r)).toList();

  static List<Map<String, dynamic>> _seedAlerts() => [
    {
      'id': 'seed-alert-1',
      'zone': 'Central Zone 1',
      'title': 'IPL Match: High Congestion Expected',
      'category': 'Event',
      'issuer': 'BTP Command Center',
      'message_en': 'High congestion expected near Chinnaswamy Stadium — IPL match tonight 19:00–23:00',
      'message_kn': 'ಚಿನ್ನಸ್ವಾಮಿ ಕ್ರೀಡಾಂಗಣದ ಸಮೀಪ ಹೆಚ್ಚಿನ ದಟ್ಟಣೆ ನಿರೀಕ್ಷಿಸಲಾಗಿದೆ',
      'severity': 0.82,
      'valid_from': DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
      'valid_until': DateTime.now().add(const Duration(hours: 5)).toIso8601String(),
      'created_at': DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
    },
    {
      'id': 'seed-alert-2',
      'zone': 'South Zone 1',
      'title': 'Silk Board Flyover Delay',
      'category': 'Accident',
      'issuer': 'South Traffic Control',
      'message_en': 'Silk Board flyover delays — accident clearance in progress',
      'message_kn': 'ಸಿಲ್ಕ್ ಬೋರ್ಡ್ ಫ್ಲೈಓವರ್‌ನಲ್ಲಿ ವಿಳಂಬ',
      'severity': 0.65,
      'valid_from': DateTime.now().subtract(const Duration(minutes: 30)).toIso8601String(),
      'valid_until': DateTime.now().add(const Duration(hours: 2)).toIso8601String(),
      'created_at': DateTime.now().subtract(const Duration(minutes: 30)).toIso8601String(),
    },
    {
      'id': 'seed-alert-3',
      'zone': 'North Zone 1',
      'title': 'Peak Hour Traffic Hebbal',
      'category': 'Traffic',
      'issuer': 'Hebbal Police Station',
      'message_en': 'Moderate traffic near Hebbal — IT corridor peak hour',
      'message_kn': 'ಹೆಬ್ಬಾಳ ಬಳಿ ಮಧ್ಯಮ ದಟ್ಟಣೆ',
      'severity': 0.48,
      'valid_from': DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
      'valid_until': DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
      'created_at': DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
    },
  ];

  static List<Map<String, dynamic>> _seedEvents() => [
    {
      'id': 'FKID000001',
      'name': 'IPL Match: RCB vs CSK',
      'type': 'planned',
      'event_category': 'ipl',
      'location_name': 'M. Chinnaswamy Stadium',
      'lat': 12.9785,
      'lng': 77.5996,
      'zone': 'Central Zone 1',
      'start_time': DateTime.now().add(const Duration(hours: 8)).toIso8601String(),
      'end_time': DateTime.now().add(const Duration(hours: 12)).toIso8601String(),
      'expected_attendance': 35000,
      'created_at': DateTime.now().subtract(const Duration(days: 2)).toIso8601String(),
    },
    {
      'id': 'FKID000002',
      'name': 'Rajyotsava Parade',
      'type': 'planned',
      'event_category': 'festival',
      'location_name': 'MG Road',
      'lat': 12.9758,
      'lng': 77.6071,
      'zone': 'Central Zone 2',
      'start_time': DateTime.now().add(const Duration(days: 3, hours: 9)).toIso8601String(),
      'end_time': DateTime.now().add(const Duration(days: 3, hours: 12)).toIso8601String(),
      'expected_attendance': 50000,
      'created_at': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
    },
    {
      'id': 'FKID000003',
      'name': 'Tech Summit 2026',
      'type': 'planned',
      'event_category': 'other',
      'location_name': 'KTPO Whitefield',
      'lat': 12.9698,
      'lng': 77.7499,
      'zone': 'East Zone 1',
      'start_time': DateTime.now().add(const Duration(days: 2, hours: 9)).toIso8601String(),
      'end_time': DateTime.now().add(const Duration(days: 2, hours: 18)).toIso8601String(),
      'expected_attendance': 8000,
      'created_at': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
    },
  ];

  static List<Map<String, dynamic>> _seedComplaints() => [
    {
      'id': 'comp-001',
      'title': 'Rider without helmet near junction',
      'violation_type': 'Helmet violation',
      'description': 'Two-wheeler rider carrying a pillion passenger, both without helmets. Driving at high speed.',
      'lat': 12.9352,
      'lng': 77.6245,
      'status': 'pending',
      'confidence_score': 0.72,
      'severity': 0.60,
      'is_volunteer': false,
      'zone': 'South Zone 1',
      'image_path': 'https://images.unsplash.com/photo-1444491741275-3747c53c99b4?w=500',
      'submitted_at': DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
    },
    {
      'id': 'comp-002',
      'title': 'SUV blocking pedestrian crossing',
      'violation_type': 'Illegal parking',
      'description': 'A white SUV parked completely over the zebra crossing, forcing pedestrians to walk on the busy road.',
      'lat': 12.9177,
      'lng': 77.6233,
      'status': 'valid',
      'confidence_score': 0.91,
      'severity': 0.85,
      'is_volunteer': true,
      'zone': 'South Zone 2',
      'image_path': 'https://images.unsplash.com/photo-1549317661-bd32c8ce0db2?w=500',
      'submitted_at': DateTime.now().subtract(const Duration(hours: 4)).toIso8601String(),
    },
    {
      'id': 'comp-003',
      'title': 'Auto-rickshaw driving on wrong side',
      'violation_type': 'Wrong side driving',
      'description': 'An auto-rickshaw drove against the traffic flow for 200m to take a shortcut, causing near-misses.',
      'lat': 13.0088,
      'lng': 77.5867,
      'status': 'invalid',
      'confidence_score': 0.32,
      'severity': 0.90,
      'is_volunteer': false,
      'zone': 'North Zone 1',
      'image_path': 'https://images.unsplash.com/photo-1506015391300-4802dc74de2e?w=500',
      'rejection_reason': 'Image too blurry for vehicle identification',
      'submitted_at': DateTime.now().subtract(const Duration(hours: 6)).toIso8601String(),
    },
  ];

  static List<Map<String, dynamic>> _seedVolunteers() => [
    {
      'id': 'vol-001',
      'junction': 'Silk Board Junction',
      'date': DateTime.now().add(const Duration(days: 1)).toIso8601String(),
      'start_time': '17:00:00',
      'end_time': '21:00:00',
      'status': 'pending',
      'created_at': DateTime.now().subtract(const Duration(hours: 3)).toIso8601String(),
    },
    {
      'id': 'vol-002',
      'junction': 'Mekhri Circle',
      'date': DateTime.now().add(const Duration(days: 2)).toIso8601String(),
      'start_time': '08:00:00',
      'end_time': '12:00:00',
      'status': 'approved',
      'created_at': DateTime.now().subtract(const Duration(hours: 5)).toIso8601String(),
    },
  ];

  static List<Map<String, dynamic>> _seedOfficers() => [
    {'id': 'off-001', 'badge_number': 'B-2241', 'name': 'Ravi Kumar',   'zone': 'Central Zone 1', 'shift_start': '06:00', 'shift_end': '14:00', 'available': true},
    {'id': 'off-002', 'badge_number': 'B-1892', 'name': 'Priya Sharma', 'zone': 'South Zone 1',   'shift_start': '14:00', 'shift_end': '22:00', 'available': true},
    {'id': 'off-003', 'badge_number': 'B-3301', 'name': 'Mohan Das',    'zone': 'North Zone 1',   'shift_start': '22:00', 'shift_end': '06:00', 'available': false},
    {'id': 'off-004', 'badge_number': 'B-4412', 'name': 'Anitha Rao',   'zone': 'East Zone 1',    'shift_start': '06:00', 'shift_end': '14:00', 'available': true},
    {'id': 'off-005', 'badge_number': 'B-5523', 'name': 'Suresh B',     'zone': 'West Zone 1',    'shift_start': '14:00', 'shift_end': '22:00', 'available': true},
    {'id': 'off-006', 'badge_number': 'B-6634', 'name': 'Kavitha M',    'zone': 'Central Zone 2', 'shift_start': '06:00', 'shift_end': '14:00', 'available': true},
    {'id': 'off-007', 'badge_number': 'B-7745', 'name': 'Rajesh Gowda', 'zone': 'South Zone 2',   'shift_start': '14:00', 'shift_end': '22:00', 'available': true},
    {'id': 'off-008', 'badge_number': 'B-8856', 'name': 'Deepa S',      'zone': 'North Zone 2',   'shift_start': '06:00', 'shift_end': '14:00', 'available': false},
  ];

  static List<Map<String, dynamic>> _seedDeployments() => [
    {
      'id': 'dep-001',
      'junction': 'Silk Board Junction',
      'lat': 12.9177, 'lng': 77.6233,
      'start_time': DateTime.now().add(const Duration(hours: 2)).toIso8601String(),
      'end_time': DateTime.now().add(const Duration(hours: 6)).toIso8601String(),
      'priority': 'high',
      'source': 'preact',
      'confirmed': false,
      'officers': {'name': 'Priya Sharma', 'badge_number': 'B-1892', 'zone': 'South Zone 1'},
    },
    {
      'id': 'dep-002',
      'junction': 'Mekhri Circle',
      'lat': 13.0088, 'lng': 77.5867,
      'start_time': DateTime.now().add(const Duration(hours: 3)).toIso8601String(),
      'end_time': DateTime.now().add(const Duration(hours: 7)).toIso8601String(),
      'priority': 'medium',
      'source': 'preact',
      'confirmed': true,
      'officers': {'name': 'Ravi Kumar', 'badge_number': 'B-2241', 'zone': 'Central Zone 1'},
    },
  ];
}
