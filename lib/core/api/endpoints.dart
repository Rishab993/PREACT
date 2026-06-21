import '../config/app_config.dart';

class AppEndpoints {
  AppEndpoints._();

  static String get apiBase => AppConfig.apiBase;

  // ── Core ──────────────────────────────────────────────────────────────────
  static String get health   => '$apiBase/api/health';
  static String get events   => '$apiBase/api/events';

  // ── Officers ──────────────────────────────────────────────────────────────
  static String get officers        => '$apiBase/api/officers';

  // ── Intelligence ──────────────────────────────────────────────────────────
  static String get forecast        => '$apiBase/api/forecast';
  static String forecastByZone(String zone) => '$apiBase/api/forecast/$zone';
  static String get deploy          => '$apiBase/api/deploy';
  static String get counterfactual  => '$apiBase/api/counterfactual';
  static String shadow(String eventId) => '$apiBase/api/shadow/$eventId';

  // ── Citizen ───────────────────────────────────────────────────────────────
  static String get complaints => '$apiBase/api/complaints';
  static String get chat       => '$apiBase/api/chat';
  static String get alerts     => '$apiBase/api/alerts';
  static String alertById(String id) => '$apiBase/api/alerts/$id';

  // ── Volunteer ─────────────────────────────────────────────────────────────
  static String get volunteerSignup    => '$apiBase/api/volunteer/signup';
  static String get volunteers         => '$apiBase/api/volunteer';
  static String volunteerById(String id) => '$apiBase/api/volunteer/$id';

  // ── Scenario Simulator ────────────────────────────────────────────────────
  static String get simulate => '$apiBase/api/simulate';

  // ── Ground Truth ──────────────────────────────────────────────────────────
  static String get groundTruth => '$apiBase/api/ground-truth';

  // ── Institutional Memory ──────────────────────────────────────────────────
  static String get memorySearch   => '$apiBase/api/memory/search';
  static String memorySimilar(String eventId) =>
      '$apiBase/api/memory/similar/$eventId';
}

// ── App Constants ─────────────────────────────────────────────────────────────
class AppConstants {
  AppConstants._();

  // Bengaluru city center
  static const double cityLat = 12.9716;
  static const double cityLng = 77.5946;

  // 10 exact zone names from spec
  static const List<String> zones = [
    'Central Zone 1',
    'Central Zone 2',
    'North Zone 1',
    'North Zone 2',
    'South Zone 1',
    'South Zone 2',
    'East Zone 1',
    'East Zone 2',
    'West Zone 1',
    'West Zone 2',
  ];

  // Key junctions with real Bengaluru coordinates
  static const List<Map<String, dynamic>> junctions = [
    {'name': 'Mekhri Circle',                       'lat': 13.0088, 'lng': 77.5867},
    {'name': 'Silk Board Junction',                 'lat': 12.9177, 'lng': 77.6233},
    {'name': 'Hebbal Flyover Junction',             'lat': 13.0452, 'lng': 77.5970},
    {'name': 'Jalahalli Cross',                     'lat': 13.0487, 'lng': 77.5516},
    {'name': 'Koramangala Water Tank Junction',     'lat': 12.9352, 'lng': 77.6245},
    {'name': 'Mysore Road Junction',                'lat': 12.9577, 'lng': 77.5066},
    {'name': 'Tin Factory Junction',                'lat': 12.9987, 'lng': 77.6600},
    {'name': 'Bannerghatta Road Junction',          'lat': 12.8932, 'lng': 77.5972},
    {'name': 'Marathahalli Bridge',                 'lat': 12.9591, 'lng': 77.7010},
    {'name': 'Electronic City Tollgate',            'lat': 12.8468, 'lng': 77.6605},
    {'name': 'Rajajinagar Junction',                'lat': 12.9849, 'lng': 77.5551},
    {'name': 'Madiwala Check Post',                 'lat': 12.9253, 'lng': 77.6196},
  ];

  // Event categories
  static const List<String> eventCategories = [
    'ipl', 'rally', 'festival', 'protest', 'other',
  ];

  // Complaint incident types (backend spec)
  static const List<String> violationTypes = [
    'accident',
    'illegal_parking',
    'traffic_violation',
    'signal_failure',
    'road_block',
    'tree_fall',
    'congestion',
    'other',
  ];

  static String violationTypeLabel(String value) {
    switch (value) {
      case 'accident': return 'Accident';
      case 'illegal_parking': return 'Illegal Parking';
      case 'traffic_violation': return 'Traffic Violation';
      case 'signal_failure': return 'Signal Failure';
      case 'road_block': return 'Road Block';
      case 'tree_fall': return 'Tree Fall';
      case 'congestion': return 'Congestion';
      case 'other': return 'Other';
      case 'vehicle_breakdown': return 'Vehicle Breakdown';
      case 'pot_holes': return 'Pot Holes';
      case 'water_logging': return 'Water Logging';
      case 'road_conditions': return 'Road Conditions';
      case 'others': return 'Others';
      case 'Helmet violation': return 'Helmet Violation';
      case 'Seatbelt violation': return 'Seatbelt Violation';
      case 'Triple riding': return 'Triple Riding';
      case 'Wrong side driving': return 'Wrong Side Driving';
      case 'Illegal parking': return 'Illegal Parking';
      case 'Red light jumping': return 'Red Light Jumping';
      case 'Speeding': return 'Speeding';
      case 'Mobile phone use': return 'Mobile Phone Use';
      default: return value;
    }
  }

  // Ground truth bottleneck options
  static const List<String> bottleneckOptions = [
    'parking_overflow',
    'pedestrian_surge',
    'vip_movement',
    'media_vans',
    'weather_event',
    'other',
  ];

  static const List<String> bottleneckLabels = [
    'Parking overflow',
    'Pedestrian surge',
    'VIP movement',
    'Media vans',
    'Weather event',
    'Other',
  ];

  // Slider debounce ms
  static const int simulatorDebounceMs = 400;

  // AI carousel interval
  static const int carouselIntervalSeconds = 5;
}
