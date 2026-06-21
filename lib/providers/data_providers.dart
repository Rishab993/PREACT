import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/auth/supabase_service.dart';
import '../core/api/api_client.dart';
import '../core/api/api_parsers.dart';
import '../core/api/endpoints.dart';
import '../core/bootstrap/startup_timer.dart';
import '../shared/models/models.dart';

const alertsRefreshInterval = Duration(seconds: 15);

List<AlertModel> sortAlerts(List<AlertModel> alerts) {
  final sorted = List<AlertModel>.from(alerts);
  sorted.sort((a, b) {
    final severityCompare = b.severity.compareTo(a.severity);
    if (severityCompare != 0) return severityCompare;
    final aTime = a.createdAt ?? a.validFrom ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bTime = b.createdAt ?? b.validFrom ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bTime.compareTo(aTime);
  });
  return sorted;
}

Future<List<AlertModel>> fetchAlertsFromApi() async {
  final response = await ApiClient.instance.get(AppEndpoints.alerts);
  final rows = ApiParsers.asMapList(response.data, keys: const ['alerts', 'data', 'items']);
  final alerts = rows.map(AlertModel.fromJson).toList();
  return sortAlerts(alerts);
}

Future<List<AlertModel>> fetchAlertsWithFallback() async {
  try {
    return await fetchAlertsFromApi();
  } catch (e) {
    debugPrint('[Alerts] GET /api/alerts failed: $e');
    return [];
  }
}

/// In-memory cache so KPI + dashboard + alerts screen share one fetch.
List<AlertModel>? _alertsCache;
DateTime? _alertsCacheAt;
const _alertsCacheTtl = Duration(seconds: 15);

Future<List<AlertModel>> fetchAlertsCached({bool forceRefresh = false}) async {
  final now = DateTime.now();
  if (!forceRefresh &&
      _alertsCache != null &&
      _alertsCacheAt != null &&
      now.difference(_alertsCacheAt!) < _alertsCacheTtl) {
    debugPrint('[fetchAlertsCached] Using cached alerts: ${_alertsCache!.length}');
    return _alertsCache!;
  }
  debugPrint('[fetchAlertsCached] Fetching fresh alerts');
  final alerts = await fetchAlertsWithFallback();
  _alertsCache = alerts;
  _alertsCacheAt = now;
  debugPrint('[fetchAlertsCached] Got ${alerts.length} alerts');
  return alerts;
}

void invalidateAlertsCache() {
  _alertsCache = null;
  _alertsCacheAt = null;
}

Future<List<EventModel>> fetchEventsFromApi() async {
  final response = await ApiClient.instance.get(AppEndpoints.events);
  final rows = ApiParsers.asMapList(response.data, keys: const ['events', 'data', 'items']);
  return rows
      .map(EventModel.fromJson)
      .where((event) => event.id.isNotEmpty)
      .toList();
}

Future<List<OfficerModel>> fetchOfficersWithFallback() async {
  try {
    final response = await ApiClient.instance.get(AppEndpoints.officers);
    if (response.statusCode != null && response.statusCode! >= 400) {
      throw ApiException('Officers endpoint unavailable', response.statusCode);
    }
    final rows = ApiParsers.asMapList(response.data, keys: const ['officers', 'data', 'items']);
    if (rows.isNotEmpty) {
      return rows.map(OfficerModel.fromJson).toList();
    }
  } catch (e) {
    debugPrint('[Officers] GET /api/officers failed: $e');
  }
  final rows = await SupabaseService.instance.fetchOfficers();
  final officers = rows.map(OfficerModel.fromJson).toList();
  if (officers.isNotEmpty) return officers;
  return SupabaseService.seedOfficerModels();
}

Future<List<VolunteerModel>> fetchVolunteersFromApi({String? status}) async {
  final response = await ApiClient.instance.get(AppEndpoints.volunteers);
  final rows = ApiParsers.asMapList(response.data, keys: const ['volunteers', 'data', 'items']);
  var volunteers = rows.map(VolunteerModel.fromJson).toList();
  if (status != null) {
    volunteers = volunteers.where((v) => v.status == status).toList();
  }
  return volunteers;
}

Future<List<VolunteerModel>> fetchVolunteersWithFallback({String? status}) async {
  try {
    return await fetchVolunteersFromApi(status: status);
  } catch (e) {
    debugPrint('[Volunteers] GET /api/volunteer failed: $e');
  }
  final rows = await SupabaseService.instance.fetchVolunteers(status: status);
  return rows.map(VolunteerModel.fromJson).toList();
}

// ─── Alerts Provider (shared cache) ───────────────────────────────────────────
final alertsProvider = FutureProvider<List<AlertModel>>((ref) async {
  ref.keepAlive();
  return fetchAlertsCached();
});

// ─── KPI: alert count only (fast path for dashboard) ──────────────────────────
final kpiAlertsProvider = FutureProvider<int>((ref) async {
  final alerts = await ref.watch(alertsProvider.future);
  return alerts.length;
});

// ─── KPI: secondary stats (deferred — not on critical startup path) ───────────
final kpiSecondaryProvider = FutureProvider<Map<String, int>>((ref) async {
  ref.keepAlive();
  try {
    final results = await Future.wait([
      ref.read(eventsProvider.future).catchError((_) => <EventModel>[]),
      ref.read(officersApiProvider.future).catchError((_) => <OfficerModel>[]),
      fetchVolunteersWithFallback(status: 'pending').catchError((_) => <VolunteerModel>[]),
      ref.read(complaintsProvider.future).catchError((_) => <ComplaintModel>[]),
    ]);

    final events = results[0] as List<EventModel>;
    final officers = results[1] as List<OfficerModel>;
    final volunteers = results[2] as List<VolunteerModel>;
    final complaints = results[3] as List<ComplaintModel>;

    return {
      'active_events': events.where((e) => e.isActive || e.status == null).length,
      'open_complaints': complaints.where((c) => c.status == 'pending').length,
      'officers_deployed': officers.where((o) => o.available).length,
      'volunteers_pending': volunteers.length,
    };
  } catch (_) {
    return {
      'active_events': 0,
      'open_complaints': 0,
      'officers_deployed': 0,
      'volunteers_pending': 0,
    };
  }
});

// ─── Officers (Backend-first, Supabase fallback) ──────────────────────────────
final officersApiProvider = FutureProvider<List<OfficerModel>>((ref) async {
  ref.keepAlive();
  return fetchOfficersWithFallback();
});

// ─── Events Provider (Backend-first) ─────────────────────────────────────────
final eventsProvider = FutureProvider<List<EventModel>>((ref) async {
  try {
    final events = await fetchEventsFromApi();
    if (events.isNotEmpty) return events;
  } catch (e) {
    debugPrint('[Events] GET /api/events failed: $e');
  }
  final rows = await SupabaseService.instance.fetchEvents();
  return rows
      .map(EventModel.fromJson)
      .where((event) => event.id.isNotEmpty)
      .toList();
});

// ─── Officers Provider ────────────────────────────────────────────────────────
final officersProvider = FutureProvider<List<OfficerModel>>((ref) async {
  return ref.watch(officersApiProvider.future);
});

// ─── Complaints Provider ──────────────────────────────────────────────────────
Future<List<ComplaintModel>> fetchComplaintsFromApi() async {
  final response = await ApiClient.instance.get(AppEndpoints.complaints);
  final rows = ApiParsers.asMapList(response.data, keys: const ['complaints', 'data', 'items']);
  return rows.map(ComplaintModel.fromJson).toList();
}

final complaintsProvider = FutureProvider<List<ComplaintModel>>((ref) async {
  StartupTimer.mark('Complaints load requested');
  try {
    return await fetchComplaintsFromApi();
  } catch (e) {
    debugPrint('[Complaints] GET /api/complaints failed: $e');
  }
  final rows = await SupabaseService.instance.fetchComplaints();
  return rows.map(ComplaintModel.fromJson).toList();
});

final complaintsListProvider = FutureProvider<List<ComplaintModel>>((ref) async {
  return ref.watch(complaintsProvider.future);
});

// ─── Forecasts Provider ───────────────────────────────────────────────────────
final forecastsProvider = FutureProvider.family<List<ForecastModel>, String?>((ref, zone) async {
  final rows = await SupabaseService.instance.fetchForecasts(zone: zone);
  if (rows.isEmpty) return _seedForecasts(zone ?? 'Central Zone 1');
  return rows.map((r) => ForecastModel.fromJson(r)).toList();
});

List<ForecastModel> _seedForecasts(String zone) {
  final now = DateTime.now();
  return List.generate(72, (i) {
    final hour = now.add(Duration(hours: i));
    final h = hour.hour;
    double sev = 0.3;
    if (h >= 8 && h <= 10) sev = 0.72;
    if (h >= 17 && h <= 20) sev = 0.85;
    if (h >= 11 && h <= 16) sev = 0.45;
    return ForecastModel(
      id: 'seed-$i',
      zone: zone,
      forecastHour: hour,
      severity: sev + (0.05 * (i % 3 - 1)),
      confidenceLower: sev - 0.1,
      confidenceUpper: sev + 0.1,
    );
  });
}

// ─── Deployments Provider ─────────────────────────────────────────────────────
final deploymentsProvider = FutureProvider.family<List<DeploymentModel>, String?>((ref, eventId) async {
  final rows = await SupabaseService.instance.fetchDeployments(eventId: eventId);
  return rows.map((r) => DeploymentModel.fromJson(r)).toList();
});

// ─── Volunteers Provider ──────────────────────────────────────────────────────
final volunteersProvider = FutureProvider.family<List<VolunteerModel>, String?>((ref, status) async {
  return fetchVolunteersWithFallback(status: status);
});

// ─── Simulations Provider ─────────────────────────────────────────────────────
final simulationsProvider = FutureProvider.family<List<SimulationModel>, String?>((ref, eventId) async {
  final rows = await SupabaseService.instance.fetchSimulations(eventId: eventId);
  return rows.map((r) => SimulationModel.fromJson(r)).toList();
});

// ─── Memory Search Provider ───────────────────────────────────────────────────
final memorySearchProvider = FutureProvider.family<List<DebriefModel>, MemorySearchParams>((ref, params) async {
  try {
    final queryParams = <String, dynamic>{};
    if (params.query.isNotEmpty) queryParams['q'] = params.query;
    if (params.zone != null) queryParams['zone'] = params.zone;
    if (params.eventType != null) queryParams['event_type'] = params.eventType;
    if (params.minAttendance > 0) queryParams['min_attendance'] = params.minAttendance;

    final response = await ApiClient.instance.get(
      AppEndpoints.memorySearch,
      queryParameters: queryParams,
    );
    final data = response.data;
    if (data is List) {
      return data.map((r) => DebriefModel.fromJson(r as Map<String, dynamic>)).toList();
    }
    return _seedDebriefs();
  } catch (_) {
    return _seedDebriefs();
  }
});

List<DebriefModel> _seedDebriefs() => [
  DebriefModel(
    id: 'deb-001',
    eventName: 'IPL RCB vs CSK',
    locationName: 'M. Chinnaswamy Stadium',
    expectedAttendance: 35000,
    preactCongestionEstimate: 54,
    actualCongestion: 87,
    congestionAvoidedMinutes: 33,
    regretScore: 0.38,
    topIntervention: 'Diversion Route B cut delays by 28%',
    missedOpportunity: 'Chinnaswamy Gate 2 was understaffed',
    createdAt: DateTime.now().subtract(const Duration(days: 30)),
  ),
  DebriefModel(
    id: 'deb-002',
    eventName: 'Rajyotsava Parade',
    locationName: 'MG Road',
    expectedAttendance: 50000,
    preactCongestionEstimate: 42,
    actualCongestion: 48,
    congestionAvoidedMinutes: 6,
    regretScore: 0.12,
    topIntervention: 'Pre-positioning at Brigade Road worked well',
    missedOpportunity: 'Late barricade setup at Residency Road',
    createdAt: DateTime.now().subtract(const Duration(days: 60)),
  ),
  DebriefModel(
    id: 'deb-003',
    eventName: 'Bengaluru Marathon',
    locationName: 'Cubbon Park',
    expectedAttendance: 25000,
    preactCongestionEstimate: 38,
    actualCongestion: 95,
    congestionAvoidedMinutes: 0,
    regretScore: 0.61,
    topIntervention: 'N/A — Plan not followed',
    missedOpportunity: 'No diversion strategy planned for Kasturba Road',
    createdAt: DateTime.now().subtract(const Duration(days: 90)),
  ),
];

class MemorySearchParams {
  final String query;
  final String? zone;
  final String? eventType;
  final int minAttendance;

  const MemorySearchParams({
    this.query = '',
    this.zone,
    this.eventType,
    this.minAttendance = 0,
  });

  @override
  bool operator ==(Object other) =>
      other is MemorySearchParams &&
      other.query == query &&
      other.zone == zone &&
      other.eventType == eventType &&
      other.minAttendance == minAttendance;

  @override
  int get hashCode => Object.hash(query, zone, eventType, minAttendance);
}

// ─── KPI Summary Provider (alerts first, secondary stats merged when ready) ──
final kpiProvider = FutureProvider<Map<String, int>>((ref) async {
  final alertCount = await ref.watch(kpiAlertsProvider.future);
  final secondary = ref.watch(kpiSecondaryProvider).maybeWhen(
        data: (value) => value,
        orElse: () => const {
          'active_events': 0,
          'open_complaints': 0,
          'officers_deployed': 0,
          'volunteers_pending': 0,
        },
      );

  return {
    'active_alerts': alertCount,
    ...secondary,
  };
});
