// ─── Shared JSON helpers ─────────────────────────────────────────────────────
String? _cleanJsonString(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  if (text.isEmpty || text.toUpperCase() == 'NULL') return null;
  return text;
}

DateTime? _parseJsonDate(dynamic value) {
  final text = _cleanJsonString(value);
  if (text == null) return null;
  return DateTime.tryParse(text);
}

String _eventDisplayName(Map<String, dynamic> json, String id) {
  for (final key in ['name', 'event_name', 'title']) {
    final value = _cleanJsonString(json[key]);
    if (value != null) return value;
  }
  final description = _cleanJsonString(json['description']);
  if (description != null) {
    return description.length > 80 ? '${description.substring(0, 80)}…' : description;
  }
  final cause = _cleanJsonString(json['event_cause']);
  if (cause != null) return cause.replaceAll('_', ' ');
  return id.isNotEmpty ? id : 'Event';
}

// ─── Event Model ─────────────────────────────────────────────────────────────
class EventModel {
  final String id;
  final String name;
  final String? type;
  final String? eventCategory;
  final String? locationName;
  final double? lat;
  final double? lng;
  final String? zone;
  final String? status;
  final DateTime? startTime;
  final DateTime? endTime;
  final int? expectedAttendance;
  final DateTime? createdAt;

  EventModel({
    required this.id,
    required this.name,
    this.type,
    this.eventCategory,
    this.locationName,
    this.lat,
    this.lng,
    this.zone,
    this.status,
    this.startTime,
    this.endTime,
    this.expectedAttendance,
    this.createdAt,
  });

  factory EventModel.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? json['event_id']?.toString() ?? '';
    return EventModel(
      id: id,
      name: _eventDisplayName(json, id),
      type: _cleanJsonString(json['type'] ?? json['event_cause']),
      eventCategory: _cleanJsonString(json['event_category'] ?? json['event_cause']),
      locationName: _cleanJsonString(json['location_name'] ?? json['corridor'] ?? json['junction']),
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      zone: _cleanJsonString(json['zone']),
      status: _cleanJsonString(json['status']),
      startTime: _parseJsonDate(json['start_time'] ?? json['start_dt']),
      endTime: _parseJsonDate(json['end_time'] ?? json['end_datetime']),
      expectedAttendance: (json['expected_attendance'] as num?)?.toInt(),
      createdAt: _parseJsonDate(json['created_at']),
    );
  }

  bool get isActive => status?.toLowerCase() == 'active';
  bool get isUpcoming => startTime != null && startTime!.isAfter(DateTime.now());
  bool get isCompleted => endTime != null && endTime!.isBefore(DateTime.now());

  String get categoryDisplay {
    switch (eventCategory?.toLowerCase()) {
      case 'ipl': return 'IPL';
      case 'rally': return 'Political Rally';
      case 'festival': return 'Festival';
      case 'protest': return 'Protest';
      default: return 'Other';
    }
  }

  String get attendanceDisplay {
    if (expectedAttendance == null) return 'N/A';
    if (expectedAttendance! >= 1000) {
      return '${(expectedAttendance! / 1000).toStringAsFixed(0)}K';
    }
    return expectedAttendance.toString();
  }
}

// ─── Alert Model ─────────────────────────────────────────────────────────────
class AlertModel {
  final String id;
  final String zone;
  final String? messageEn;
  final String? messageKn;
  final double severity;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final DateTime? createdAt;
  final String? title;
  final String? category;
  final String? issuer;

  AlertModel({
    required this.id,
    required this.zone,
    this.messageEn,
    this.messageKn,
    this.severity = 0.5,
    this.validFrom,
    this.validUntil,
    this.createdAt,
    this.title,
    this.category,
    this.issuer,
  });

  factory AlertModel.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    final createdAtRaw = json['created_at']?.toString();
    return AlertModel(
      id: id.isNotEmpty ? id : 'alert-${createdAtRaw ?? json.hashCode}',
      zone: json['zone']?.toString() ?? '',
      messageEn: json['message_en']?.toString(),
      messageKn: json['message_kn']?.toString(),
      severity: (json['severity'] as num?)?.toDouble() ?? 0.5,
      validFrom: json['valid_from'] != null ? DateTime.tryParse(json['valid_from'].toString()) : null,
      validUntil: json['valid_until'] != null ? DateTime.tryParse(json['valid_until'].toString()) : null,
      createdAt: createdAtRaw != null ? DateTime.tryParse(createdAtRaw) : null,
      title: json['title']?.toString(),
      category: json['category']?.toString(),
      issuer: json['issuer']?.toString(),
    );
  }

  String severityLabel() {
    if (severity >= 0.8) return 'CRITICAL';
    if (severity >= 0.6) return 'HIGH';
    if (severity >= 0.4) return 'MEDIUM';
    return 'LOW';
  }

  bool get isActive => validUntil == null || validUntil!.isAfter(DateTime.now());

  String get timeAgo {
    if (createdAt == null) return '';
    final diff = DateTime.now().difference(createdAt!);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ─── Forecast Model ───────────────────────────────────────────────────────────
class ForecastModel {
  final String id;
  final String? eventId;
  final String zone;
  final DateTime forecastHour;
  final double severity;
  final double? confidenceLower;
  final double? confidenceUpper;
  final String? modelVersion;
  final DateTime? createdAt;

  ForecastModel({
    required this.id,
    this.eventId,
    required this.zone,
    required this.forecastHour,
    required this.severity,
    this.confidenceLower,
    this.confidenceUpper,
    this.modelVersion,
    this.createdAt,
  });

  factory ForecastModel.fromJson(Map<String, dynamic> json) => ForecastModel(
    id: json['id']?.toString() ?? '',
    eventId: json['event_id']?.toString(),
    zone: json['zone']?.toString() ?? '',
    forecastHour: json['forecast_hour'] != null
        ? DateTime.parse(json['forecast_hour'])
        : DateTime.now(),
    severity: (json['severity'] as num?)?.toDouble() ?? 0.0,
    confidenceLower: (json['confidence_lower'] as num?)?.toDouble(),
    confidenceUpper: (json['confidence_upper'] as num?)?.toDouble(),
    modelVersion: json['model_version']?.toString(),
    createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at']) : null,
  );

  String get severityTier {
    if (severity >= 0.9) return 'CRITICAL';
    if (severity >= 0.7) return 'HIGH';
    if (severity >= 0.4) return 'MEDIUM';
    return 'LOW';
  }

  double get severityPercent => severity * 100;
}

// ─── Deployment Model ─────────────────────────────────────────────────────────
class DeploymentModel {
  final String id;
  final String? eventId;
  final String? officerId;
  final String junction;
  final double? lat;
  final double? lng;
  final DateTime? startTime;
  final DateTime? endTime;
  final String priority;
  final String source;
  final bool confirmed;
  final DateTime? createdAt;
  // Joined officer data
  final String? officerName;
  final String? officerBadge;
  final String? officerZone;

  DeploymentModel({
    required this.id,
    this.eventId,
    this.officerId,
    required this.junction,
    this.lat,
    this.lng,
    this.startTime,
    this.endTime,
    this.priority = 'medium',
    this.source = 'preact',
    this.confirmed = false,
    this.createdAt,
    this.officerName,
    this.officerBadge,
    this.officerZone,
  });

  factory DeploymentModel.fromJson(Map<String, dynamic> json) {
    final officerData = json['officers'];
    final name = json['officer_name']?.toString() ?? (officerData is Map ? officerData['name']?.toString() : null);
    final badge = json['officer_badge']?.toString() ?? (officerData is Map ? officerData['badge_number']?.toString() : null);
    final zone = json['officer_zone']?.toString() ?? (officerData is Map ? officerData['zone']?.toString() : null);

    return DeploymentModel(
      id: json['id']?.toString() ?? '',
      eventId: json['event_id']?.toString(),
      officerId: json['officer_id']?.toString(),
      junction: json['junction']?.toString() ?? '',
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      startTime: json['start_time'] != null ? DateTime.tryParse(json['start_time']) : null,
      endTime: json['end_time'] != null ? DateTime.tryParse(json['end_time']) : null,
      priority: json['priority']?.toString() ?? 'medium',
      source: json['source']?.toString() ?? 'manual',
      confirmed: json['confirmed'] as bool? ?? false,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at']) : null,
      officerName: name,
      officerBadge: badge,
      officerZone: zone,
    );
  }
}

// ─── Officer Model ────────────────────────────────────────────────────────────
class OfficerModel {
  final String id;
  final String badgeNumber;
  final String name;
  final String zone;
  final String? shiftStart;
  final String? shiftEnd;
  final bool available;

  OfficerModel({
    required this.id,
    required this.badgeNumber,
    required this.name,
    required this.zone,
    this.shiftStart,
    this.shiftEnd,
    this.available = true,
  });

  factory OfficerModel.fromJson(Map<String, dynamic> json) => OfficerModel(
    id: json['id']?.toString() ?? json['officer_id']?.toString() ?? '',
    badgeNumber: json['badge_number']?.toString() ??
        json['badge']?.toString() ??
        json['officer_badge']?.toString() ??
        '',
    name: json['name']?.toString() ?? json['officer_name']?.toString() ?? '',
    zone: json['zone']?.toString() ?? json['officer_zone']?.toString() ?? '',
    shiftStart: json['shift_start']?.toString(),
    shiftEnd: json['shift_end']?.toString(),
    available: json['available'] as bool? ?? json['is_available'] as bool? ?? true,
  );

  String get initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return parts[0].isNotEmpty ? parts[0][0].toUpperCase() : '?';
  }
}

// ─── Complaint Model ──────────────────────────────────────────────────────────
class ComplaintModel {
  final String id;
  final String? submittedBy;
  final String? title;
  final String? violationType;
  final String? description;
  final double? lat;
  final double? lng;
  final String? imagePath;
  final String status;
  final String? rejectionReason;
  final double confidenceScore;
  final double? severity;
  final bool isVolunteer;
  final String? zone;
  final DateTime? submittedAt;

  ComplaintModel({
    required this.id,
    this.submittedBy,
    this.title,
    this.violationType,
    this.description,
    this.lat,
    this.lng,
    this.imagePath,
    this.status = 'pending',
    this.rejectionReason,
    this.confidenceScore = 0.5,
    this.severity = 0.5,
    this.isVolunteer = false,
    this.zone,
    this.submittedAt,
  });

  /// Reads the image reference from any backend field name.
  static String? readImagePath(Map<String, dynamic> json) {
    for (final key in ['image_path', 'image_url', 'imageUrl', 'photo_url']) {
      final value = json[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  /// True when [path] looks like a server/storage reference, not a local filename.
  static bool isStrongImagePath(String? path) {
    if (path == null || path.isEmpty) return false;
    if (path.startsWith('http://') || path.startsWith('https://')) return true;
    if (path.startsWith('/')) return true;
    return path.contains('/');
  }

  factory ComplaintModel.fromJson(Map<String, dynamic> json) => ComplaintModel(
    id: json['id']?.toString() ?? json['complaint_id']?.toString() ?? '',
    submittedBy: json['submitted_by']?.toString(),
    title: _cleanJsonString(json['title']) ??
        _cleanJsonString(json['violation_type'])?.replaceAll('_', ' '),
    violationType: json['violation_type']?.toString(),
    description: json['description']?.toString(),
    lat: (json['lat'] as num?)?.toDouble(),
    lng: (json['lng'] as num?)?.toDouble(),
    imagePath: readImagePath(json),
    status: json['status']?.toString() ?? 'pending',
    rejectionReason: json['rejection_reason']?.toString(),
    confidenceScore: (json['confidence_score'] as num?)?.toDouble() ?? 0.5,
    severity: (json['severity'] as num?)?.toDouble() ?? 0.5,
    isVolunteer: json['is_volunteer'] as bool? ?? false,
    zone: json['zone']?.toString(),
    submittedAt: json['submitted_at'] != null ? DateTime.tryParse(json['submitted_at']) : null,
  );

  String get statusDisplay {
    switch (status) {
      case 'valid': return 'Valid';
      case 'invalid': return 'Rejected';
      case 'pending': return 'Pending';
      default: return 'Validating';
    }
  }

  String get timeAgo {
    if (submittedAt == null) return '';
    final diff = DateTime.now().difference(submittedAt!);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ─── Volunteer Model ──────────────────────────────────────────────────────────
class VolunteerModel {
  final String id;
  final String? citizenId;
  final String? date;
  final String? startTime;
  final String? endTime;
  final String junction;
  final String status;
  final String? reviewedBy;
  final DateTime? createdAt;

  VolunteerModel({
    required this.id,
    this.citizenId,
    this.date,
    this.startTime,
    this.endTime,
    required this.junction,
    this.status = 'pending',
    this.reviewedBy,
    this.createdAt,
  });

  factory VolunteerModel.fromJson(Map<String, dynamic> json) => VolunteerModel(
    id: json['id']?.toString() ?? '',
    citizenId: json['citizen_id']?.toString(),
    date: json['date']?.toString(),
    startTime: json['start_time']?.toString(),
    endTime: json['end_time']?.toString(),
    junction: json['junction']?.toString() ?? '',
    status: json['status']?.toString() ?? 'pending',
    reviewedBy: json['reviewed_by']?.toString(),
    createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at']) : null,
  );
}

// ─── Simulation Model ─────────────────────────────────────────────────────────
class SimulationModel {
  final String id;
  final String? eventId;
  final String? label;
  final Map<String, dynamic>? scenarioParams;
  final Map<String, dynamic>? predictedSeverity;
  final double? totalCongestionMin;
  final double? vsOptimalDeltaMin;
  final DateTime? createdAt;

  SimulationModel({
    required this.id,
    this.eventId,
    this.label,
    this.scenarioParams,
    this.predictedSeverity,
    this.totalCongestionMin,
    this.vsOptimalDeltaMin,
    this.createdAt,
  });

  factory SimulationModel.fromJson(Map<String, dynamic> json) => SimulationModel(
    id: json['id']?.toString() ?? '',
    eventId: json['event_id']?.toString(),
    label: json['label']?.toString(),
    scenarioParams: json['scenario_params'] as Map<String, dynamic>?,
    predictedSeverity: json['predicted_severity'] as Map<String, dynamic>?,
    totalCongestionMin: (json['total_congestion_min'] as num?)?.toDouble(),
    vsOptimalDeltaMin: (json['vs_optimal_delta_min'] as num?)?.toDouble(),
    createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at']) : null,
  );
}

// ─── Memory / Debrief Model ───────────────────────────────────────────────────
class DebriefModel {
  final String id;
  final String? eventId;
  final String? eventName;
  final String? locationName;
  final int? expectedAttendance;
  final double? preactCongestionEstimate;
  final double? actualCongestion;
  final double? congestionAvoidedMinutes;
  final double? regretScore;
  final String? topIntervention;
  final String? missedOpportunity;
  final String? notes;
  final DateTime? createdAt;

  DebriefModel({
    required this.id,
    this.eventId,
    this.eventName,
    this.locationName,
    this.expectedAttendance,
    this.preactCongestionEstimate,
    this.actualCongestion,
    this.congestionAvoidedMinutes,
    this.regretScore,
    this.topIntervention,
    this.missedOpportunity,
    this.notes,
    this.createdAt,
  });

  factory DebriefModel.fromJson(Map<String, dynamic> json) => DebriefModel(
    id: json['id']?.toString() ?? '',
    eventId: json['event_id']?.toString(),
    eventName: json['name']?.toString() ?? json['event_name']?.toString(),
    locationName: json['location_name']?.toString(),
    expectedAttendance: (json['expected_attendance'] as num?)?.toInt(),
    preactCongestionEstimate: (json['preact_congestion_estimate'] as num?)?.toDouble(),
    actualCongestion: (json['actual_congestion'] as num?)?.toDouble(),
    congestionAvoidedMinutes: (json['congestion_avoided_minutes'] as num?)?.toDouble(),
    regretScore: (json['regret_score'] as num?)?.toDouble(),
    topIntervention: json['top_intervention']?.toString(),
    missedOpportunity: json['missed_opportunity']?.toString(),
    notes: json['notes']?.toString(),
    createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at']) : null,
  );

  String get regretLabel {
    if (regretScore == null) return 'N/A';
    return '${(regretScore! * 100).toStringAsFixed(0)}%';
  }

  String get attendanceDisplay {
    if (expectedAttendance == null) return '';
    if (expectedAttendance! >= 1000) {
      return '${(expectedAttendance! / 1000).toStringAsFixed(0)}K attendees';
    }
    return '$expectedAttendance attendees';
  }
}
