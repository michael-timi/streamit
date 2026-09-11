import '../imports/core_imports.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  AppConfig._();
  static late final Dio dio;

  /// Raw value from env (may be empty).
  static String get baseUrl => _baseUrlFromEnv();

  /// Whether a backend URL was configured — skip remote auth until set.
  static bool get hasApiBaseUrl => _baseUrlFromEnv().trim().isNotEmpty;

  /// Dio requires a valid absolute base URL; use placeholder only so relative paths resolve.
  static String get _dioBaseUrl {
    final raw = _baseUrlFromEnv().trim();
    if (raw.isEmpty) {
      AppLogger.warning(
        'API_BASE_URL is empty — set assets/env/default.env (or override). '
        'Auth API calls are skipped until configured.',
      );
      return 'http://127.0.0.1';
    }
    return raw;
  }

  static Future<void> init() async {
    dio = Dio(
      BaseOptions(
        baseUrl: _dioBaseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          AppLogger.info('🌐 [DIO] REQUEST[${options.method}] => PATH: ${options.path}');
          return handler.next(options);
        },
        onResponse: (response, handler) {
          AppLogger.info('✅ [DIO] RESPONSE[${response.statusCode}] => PATH: ${response.requestOptions.path}');
          return handler.next(response);
        },
        onError: (DioException e, handler) {
          AppLogger.error('❌ [DIO] ERROR[${e.response?.statusCode}] => PATH: ${e.requestOptions.path}');
          return handler.next(e);
        },
      ),
    );

  }

  static String _baseUrlFromEnv() {
    return dotenv.get('API_BASE_URL', fallback: '');
  }
}
