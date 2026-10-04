import 'package:dio/dio.dart';

import '../config/api_config.dart';

class ApiResult {
  const ApiResult({
    required this.success,
    this.statusCode,
    this.message,
    this.data,
  });

  final bool success;
  final int? statusCode;
  final String? message;
  final dynamic data;

  factory ApiResult.success({int? statusCode, dynamic data}) {
    return ApiResult(success: true, statusCode: statusCode, data: data);
  }

  factory ApiResult.failure({int? statusCode, String? message}) {
    return ApiResult(success: false, statusCode: statusCode, message: message);
  }
}

class ApiClient {
  ApiClient({Dio? dio}) : _dio = dio ?? Dio(_createBaseOptions());

  final Dio _dio;

  static BaseOptions _createBaseOptions() {
    return BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      // The /sms endpoint blocks on LLM generation, which routinely runs past
      // 20s once a conversation has history behind it. Timing out here means
      // the backend answers, bills for it, and the reply is thrown away.
      receiveTimeout: const Duration(seconds: 120),
      sendTimeout: const Duration(seconds: 30),
      headers: ApiConfig.defaultHeaders,
      validateStatus: (status) => status != null && status < 500,
    );
  }

  Future<ApiResult> uploadIncoming(Map payload) async {
    // The backend exposes a single POST /sms endpoint that accepts
    // { phone_number, message } and returns a SmsOut { phone_number, message }.
    // Map our incoming payload to that contract.
    final mapped = <String, dynamic>{
      'phone_number': payload['sender'] ?? payload['phone_number'],
      'message': payload['body'] ?? payload['message'],
    };

    try {
      final response = await _dio.post('/sms', data: mapped);

      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        return ApiResult.success(
          statusCode: response.statusCode,
          data: response.data,
        );
      }

      return ApiResult.failure(
        statusCode: response.statusCode,
        message: 'Upload incoming failed',
      );
    } on DioException catch (error) {
      final message = _formatDioError(error);
      return ApiResult.failure(
        statusCode: error.response?.statusCode,
        message: message,
      );
    } catch (error) {
      return ApiResult.failure(
        message: 'Unexpected incoming upload error: $error',
      );
    }
  }

  /// Backend status for the dashboard: model, cache size and answer counts.
  Future<ApiResult> health() async {
    try {
      final response = await _dio.get(
        '/health',
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );
      if (response.statusCode == 200) {
        return ApiResult.success(statusCode: 200, data: response.data);
      }
      return ApiResult.failure(
        statusCode: response.statusCode,
        message: 'Health check failed',
      );
    } on DioException catch (error) {
      return ApiResult.failure(
        statusCode: error.response?.statusCode,
        message: _formatDioError(error),
      );
    } catch (error) {
      return ApiResult.failure(
        message: 'Unexpected health check error: $error',
      );
    }
  }

  Future<ApiResult> uploadOutgoing(Map payload) async {
    return _postWithRetry('/outgoing-sms', payload, label: 'outgoing');
  }

  /// Fetch outgoing tasks for the given device id.
  Future<ApiResult> fetchOutgoing(String deviceId) async {
    try {
      final response = await _dio.get(
        '/outgoing-sms',
        queryParameters: {'device_id': deviceId},
      );

      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        return ApiResult.success(
          statusCode: response.statusCode,
          data: response.data,
        );
      }

      return ApiResult.failure(
        statusCode: response.statusCode,
        message: 'Fetch outgoing failed',
      );
    } on DioException catch (error) {
      final message = _formatDioError(error);
      return ApiResult.failure(
        statusCode: error.response?.statusCode,
        message: message,
      );
    } catch (error) {
      return ApiResult.failure(
        message: 'Unexpected fetch outgoing error: $error',
      );
    }
  }

  /// Acknowledge an outgoing task result.
  Future<ApiResult> ackOutgoing(String taskId, Map payload) async {
    try {
      final response = await _dio.post(
        '/outgoing-sms/$taskId/status',
        data: payload,
      );

      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        return ApiResult.success(
          statusCode: response.statusCode,
          data: response.data,
        );
      }

      return ApiResult.failure(
        statusCode: response.statusCode,
        message: 'Ack outgoing failed',
      );
    } on DioException catch (error) {
      final message = _formatDioError(error);
      return ApiResult.failure(
        statusCode: error.response?.statusCode,
        message: message,
      );
    } catch (error) {
      return ApiResult.failure(
        message: 'Unexpected ack outgoing error: $error',
      );
    }
  }

  Future<ApiResult> _postWithRetry(
    String path,
    Map payload, {
    required String label,
    int retries = 2,
  }) async {
    var attempt = 0;

    while (true) {
      try {
        final response = await _dio.post(
          path,
          data: payload,
          options: Options(headers: ApiConfig.defaultHeaders),
        );

        if (response.statusCode != null &&
            response.statusCode! >= 200 &&
            response.statusCode! < 300) {
          return ApiResult.success(
            statusCode: response.statusCode,
            data: response.data,
          );
        }

        return ApiResult.failure(
          statusCode: response.statusCode,
          message: response.data is Map
              ? ((response.data['message'] ?? response.data['error']) ??
                    'Upload failed')
              : 'Upload failed',
        );
      } on DioException catch (error) {
        final shouldRetry =
            error.type == DioExceptionType.connectionTimeout ||
            error.type == DioExceptionType.receiveTimeout ||
            error.type == DioExceptionType.connectionError;

        if (shouldRetry && attempt < retries) {
          attempt++;
          await Future<void>.delayed(const Duration(seconds: 1));
          continue;
        }

        final message = _formatDioError(error);
        return ApiResult.failure(
          statusCode: error.response?.statusCode,
          message: message,
        );
      } catch (error) {
        return ApiResult.failure(
          message: 'Unexpected $label upload error: $error',
        );
      }
    }
  }

  String _formatDioError(DioException error) {
    if (error.response != null && error.response!.data is Map) {
      final data = error.response!.data as Map;
      return data['message']?.toString() ??
          data['error']?.toString() ??
          'Request failed';
    }

    if (error.type == DioExceptionType.connectionTimeout) {
      return 'Connection timed out';
    }
    if (error.type == DioExceptionType.receiveTimeout) {
      return 'Server timed out';
    }
    if (error.type == DioExceptionType.connectionError) {
      return 'Network connection unavailable';
    }
    if (error.type == DioExceptionType.badResponse) {
      return 'Server returned an invalid response';
    }
    return error.message ?? 'Request failed';
  }
}
