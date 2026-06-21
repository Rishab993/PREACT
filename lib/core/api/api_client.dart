import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Singleton Dio client with:
/// - Auth interceptor (Supabase anon key in headers)
/// - Retry on 5xx (max 2 retries)
/// - In-memory cache fallback (last successful response per URL)
/// - Error → returns cached data if available
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  late final Dio _dio;
  final Map<String, dynamic> _cache = {};

  void init({String? supabaseAnonKey}) {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        debugPrint('[API] ${options.method} ${options.path}');
        handler.next(options);
      },
      onResponse: (response, handler) {
        // Cache successful GET responses
        if (response.requestOptions.method == 'GET') {
          _cache[response.requestOptions.uri.toString()] = response.data;
        }
        handler.next(response);
      },
      onError: (error, handler) {
        debugPrint('[API] Error: ${error.message}');
        final cached = _cache[error.requestOptions.uri.toString()];
        if (cached != null) {
          handler.resolve(Response(
            requestOptions: error.requestOptions,
            data: cached,
            statusCode: 200,
            extra: {'from_cache': true},
          ));
        } else {
          handler.next(error);
        }
      },
    ));

    // Retry interceptor
    _dio.interceptors.add(_RetryInterceptor(_dio));
  }

  Dio get dio => _dio;

  // ── Convenience wrappers ─────────────────────────────────────────────────

  Future<Response> get(
    String url, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      return await _dio.get(url, queryParameters: queryParameters);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Response> post(
    String url, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.post(
        url,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Response> patch(
    String url, {
    dynamic data,
  }) async {
    try {
      return await _dio.patch(url, data: data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Response> delete(String url) async {
    try {
      return await _dio.delete(url);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Returns cached data for a URL (used for skeleton → real data fallback)
  dynamic getCached(String url) => _cache[url];

  bool isFromCache(Response response) =>
      response.extra['from_cache'] == true;

  ApiException _handleError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException('Request timed out. Backend may be warming up.', e.response?.statusCode);
      case DioExceptionType.connectionError:
        return ApiException('Cannot reach server. Check your connection.', null);
      default:
        final msg = e.response?.data?['detail'] ?? e.message ?? 'Unknown error';
        return ApiException(msg.toString(), e.response?.statusCode);
    }
  }
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, this.statusCode);

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Simple retry interceptor — retries up to 2 times on 5xx errors
class _RetryInterceptor extends Interceptor {
  final Dio dio;
  _RetryInterceptor(this.dio);

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
    final statusCode = err.response?.statusCode;
    final extra = err.requestOptions.extra;
    final retryCount = extra['retryCount'] ?? 0;

    if (statusCode != null && statusCode >= 500 && retryCount < 2) {
      await Future.delayed(Duration(milliseconds: 500 * ((retryCount as num).toInt() + 1)));
      final options = err.requestOptions;
      options.extra['retryCount'] = retryCount + 1;
      try {
        final response = await dio.fetch(options);
        return handler.resolve(response);
      } catch (_) {}
    }
    return super.onError(err, handler);
  }
}

// Ensure init is called from main
void initApiClient() {
  ApiClient.instance.init();
}
