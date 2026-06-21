/// Shared helpers for normalizing backend JSON list responses.
class ApiParsers {
  ApiParsers._();

  static List<Map<String, dynamic>> asMapList(dynamic data, {List<String> keys = const []}) {
    if (data is List) {
      return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    if (data is Map) {
      for (final key in keys) {
        final nested = data[key];
        if (nested is List) {
          return nested.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        }
      }
      for (final value in data.values) {
        if (value is List && value.isNotEmpty && value.first is Map) {
          return value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        }
      }
    }
    return [];
  }
}
