import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nullfeed/services/api_service.dart';

import '../helpers/test_helpers.dart';

DioException _dioError({
  DioExceptionType type = DioExceptionType.badResponse,
  int? statusCode,
  Object? data,
}) {
  final requestOptions = RequestOptions(path: '/api/test');
  return DioException(
    requestOptions: requestOptions,
    type: type,
    response: statusCode == null
        ? null
        : Response<Object?>(
            requestOptions: requestOptions,
            statusCode: statusCode,
            data: data,
          ),
  );
}

void main() {
  group('ApiException.fromDioException', () {
    test('uses the response detail when present', () {
      final exception = ApiException.fromDioException(
        _dioError(statusCode: 403, data: {'detail': 'Incorrect PIN'}),
      );

      expect(exception.message, 'Incorrect PIN');
      expect(exception.statusCode, 403);
      expect(exception.isConnectionError, isFalse);
    });

    test('maps timeouts and connection failures to a connection error', () {
      const connectionTypes = [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.connectionError,
      ];

      for (final type in connectionTypes) {
        final exception = ApiException.fromDioException(_dioError(type: type));
        expect(exception.isConnectionError, isTrue, reason: '$type');
        expect(
          exception.message,
          'Could not reach the server. Check your connection.',
          reason: '$type',
        );
      }
    });

    test('falls back to a status message when no detail is present', () {
      final exception = ApiException.fromDioException(
        _dioError(statusCode: 500, data: {'error': 'boom'}),
      );

      expect(exception.message, 'Request failed (500)');
      expect(exception.statusCode, 500);
    });

    test('ignores a non-string detail', () {
      final exception = ApiException.fromDioException(
        _dioError(statusCode: 400, data: {'detail': 42}),
      );

      expect(exception.message, 'Request failed (400)');
    });

    test('parses the machine-readable code alongside the detail', () {
      final exception = ApiException.fromDioException(
        _dioError(
          statusCode: 409,
          data: {'detail': 'Already subscribed', 'code': 'conflict'},
        ),
      );

      expect(exception.message, 'Already subscribed');
      expect(exception.code, 'conflict');
      expect(exception.statusCode, 409);
    });

    test('leaves code null when the envelope omits it', () {
      final exception = ApiException.fromDioException(
        _dioError(statusCode: 500, data: {'detail': 'boom'}),
      );

      expect(exception.code, isNull);
    });

    test('ignores a non-string code', () {
      final exception = ApiException.fromDioException(
        _dioError(statusCode: 400, data: {'detail': 'bad', 'code': 42}),
      );

      expect(exception.code, isNull);
    });

    test('falls back to a generic message when there is no response', () {
      final exception = ApiException.fromDioException(
        _dioError(type: DioExceptionType.unknown),
      );

      expect(exception.message, 'Something went wrong. Please try again.');
      expect(exception.statusCode, isNull);
      expect(exception.isConnectionError, isFalse);
    });

    test('cancellation is not treated as a connection error', () {
      final exception = ApiException.fromDioException(
        _dioError(type: DioExceptionType.cancel),
      );

      expect(exception.isConnectionError, isFalse);
    });

    test('toString returns the user-presentable message', () {
      const exception = ApiException(message: 'Incorrect PIN', statusCode: 403);
      expect(exception.toString(), 'Incorrect PIN');
    });
  });

  group('ApiService error mapping', () {
    test('wraps a failed request into an ApiException', () async {
      final storage = MockStorageService();
      // Port 1 is never listening, so the connection is refused immediately.
      when(() => storage.getServerUrl()).thenReturn('http://127.0.0.1:1');
      when(() => storage.getSessionToken()).thenReturn(null);
      final api = ApiService(storage: storage);

      await expectLater(
        api.getProfiles(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.isConnectionError,
            'isConnectionError',
            isTrue,
          ),
        ),
      );
    });
  });
}
