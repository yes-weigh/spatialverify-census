import 'package:dio/dio.dart';

/// User-facing message for failed HTTP calls (no raw Dio stack traces in UI).
String friendlyNetworkError(Object error) {
  if (error is DioException) {
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        'Could not reach the server in time. Check your internet connection and try again.',
      DioExceptionType.connectionError =>
        'Network unavailable. If you are importing an HLO map, the app can process it on this device without a server.',
      DioExceptionType.badResponse => _statusMessage(error.response?.statusCode),
      _ => 'Something went wrong while contacting the server. Please try again.',
    };
  }

  final text = error.toString();
  if (text.startsWith('Exception: ')) return text.substring(11);
  if (text.contains('DioException')) {
    return 'Could not reach the server. Check your connection and try again.';
  }
  return text;
}

String _statusMessage(int? code) {
  if (code == 401 || code == 403) return 'Session expired — sign in again.';
  if (code == 404) return 'Server endpoint not found. The app may need an update.';
  if (code != null && code >= 500) return 'Server error ($code). Try again in a few minutes.';
  return 'Request failed${code != null ? ' ($code)' : ''}. Please try again.';
}
