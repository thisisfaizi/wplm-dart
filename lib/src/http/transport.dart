import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../errors.dart';

/// A raw HTTP response (status + body) returned by a [WplmTransport].
class WplmResponse {
  const WplmResponse(this.statusCode, this.body);

  /// HTTP status code.
  final int statusCode;

  /// Raw response body.
  final String body;
}

/// Pluggable HTTP transport. Inject a custom implementation for proxies,
/// certificate pinning, or testing.
abstract class WplmTransport {
  /// Send a request and return the response, or throw [WplmNetworkError].
  Future<WplmResponse> send({
    required String method,
    required Uri url,
    Map<String, String>? headers,
    String? body,
  });

  /// Release any held resources.
  void close() {}
}

/// Default transport built on `package:http` with per-request timeouts and
/// retries (exponential backoff + jitter) for transient failures.
class HttpTransport implements WplmTransport {
  HttpTransport({
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
    this.maxRetries = 2,
  }) : _client = client ?? http.Client();

  final http.Client _client;

  /// Per-attempt timeout.
  final Duration timeout;

  /// Maximum retry attempts for transient errors (network / 429 / 5xx).
  final int maxRetries;

  static const Set<int> _retryableStatus = {429, 500, 502, 503, 504};
  final Random _random = Random();

  @override
  Future<WplmResponse> send({
    required String method,
    required Uri url,
    Map<String, String>? headers,
    String? body,
  }) async {
    Object? lastError;

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(_backoff(attempt));
      }

      try {
        final http.Request request = http.Request(method, url);
        if (headers != null) {
          request.headers.addAll(headers);
        }
        if (body != null) {
          request.body = body;
        }

        final http.StreamedResponse streamed =
            await _client.send(request).timeout(timeout);
        final String responseBody =
            await streamed.stream.bytesToString().timeout(timeout);

        if (_retryableStatus.contains(streamed.statusCode) &&
            attempt < maxRetries) {
          lastError = 'HTTP ${streamed.statusCode}';
          continue;
        }

        return WplmResponse(streamed.statusCode, responseBody);
      } on TimeoutException catch (e) {
        lastError = e;
      } on SocketException catch (e) {
        lastError = e;
      } on http.ClientException catch (e) {
        lastError = e;
      }
    }

    throw WplmNetworkError(
      'Request failed after ${maxRetries + 1} attempt(s): $lastError',
      cause: lastError,
    );
  }

  Duration _backoff(int attempt) {
    final int base = 200 * (1 << (attempt - 1)); // 200ms, 400ms, 800ms…
    final int jitter = _random.nextInt(100);
    return Duration(milliseconds: base + jitter);
  }

  @override
  void close() => _client.close();
}
