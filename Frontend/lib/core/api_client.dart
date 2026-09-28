import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import 'app_config.dart';

/// Thrown for any non-success response so screens can show the API's own message.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.errors});

  final String message;
  final int? statusCode;
  final Map<String, dynamic>? errors;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// Unwrapped { success, message, data } envelope.
class ApiResult<T> {
  ApiResult(this.data, this.message);
  final T data;
  final String message;
}

typedef TokenProvider = String? Function();
typedef UnauthorizedHandler = Future<void> Function();

class ApiClient {
  ApiClient({required this.tokenProvider, this.onUnauthorized, this.defaultQuery = const {}});

  final TokenProvider tokenProvider;
  final UnauthorizedHandler? onUnauthorized;

  /// Added to every request. The Super Admin uses a copy with {'businessId': id}
  /// to open any shop's screens exactly as the owner sees them.
  final Map<String, dynamic> defaultQuery;

  /// Same sign-in, pinned to one shop (for the Super Admin).
  ApiClient forBusiness(int businessId) => ApiClient(
        tokenProvider: tokenProvider,
        onUnauthorized: onUnauthorized,
        defaultQuery: {...defaultQuery, 'businessId': businessId},
      );

  static const _timeout = Duration(seconds: 20);

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final qp = <String, String>{};
    defaultQuery.forEach((k, v) {
      if (v != null) qp[k] = '$v';
    });
    query?.forEach((k, v) {
      if (v != null) qp[k] = '$v';
    });
    final base = Uri.parse('${AppConfig.baseUrl}$path');
    // Keep any query already in the path (e.g. an image URL with ?v=).
    final merged = {...base.queryParameters, ...qp};
    return base.replace(queryParameters: merged.isEmpty ? null : merged);
  }

  Map<String, String> _headers() {
    final headers = {'Content-Type': 'application/json'};
    final token = tokenProvider();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<ApiResult<dynamic>> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => http.get(_uri(path, query), headers: _headers()));

  Future<ApiResult<dynamic>> post(String path,
          {Object? body, Map<String, dynamic>? query}) =>
      _send(() => http.post(_uri(path, query),
          headers: _headers(), body: body == null ? null : jsonEncode(body)));

  Future<ApiResult<dynamic>> put(String path, {Object? body}) => _send(
      () => http.put(_uri(path), headers: _headers(), body: jsonEncode(body)));

  Future<ApiResult<dynamic>> delete(String path) =>
      _send(() => http.delete(_uri(path), headers: _headers()));

  /// Multipart POST for the UPI screenshot upload.
  Future<ApiResult<dynamic>> postMultipart(
    String path, {
    required Map<String, String> fields,
    List<int>? fileBytes,
    String? fileField,
    String? fileName,
    String? fileContentType,
  }) async {
    final request = http.MultipartRequest('POST', _uri(path));

    final token = tokenProvider();
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    request.fields.addAll(fields);

    if (fileBytes != null && fileField != null) {
      request.files.add(http.MultipartFile.fromBytes(
        fileField,
        fileBytes,
        filename: fileName ?? 'upload.jpg',
        contentType: fileContentType == null
            ? null
            : MediaType.parse(fileContentType),
      ));
    }

    return _send(() async {
      final streamed = await request.send();
      return http.Response.fromStream(streamed);
    });
  }

  /// Authenticated binary fetch. Used for screenshots, which Image.network
  /// cannot load on web because it cannot attach the bearer token.
  Future<Uint8List> getBytes(String path) async {
    final res = await http
        .get(_uri(path), headers: _headers())
        .timeout(const Duration(seconds: 30));

    if (res.statusCode == 401) {
      await onUnauthorized?.call();
      throw ApiException('Please log in again.', statusCode: 401);
    }
    if (res.statusCode >= 400) {
      throw ApiException('Could not load the image.', statusCode: res.statusCode);
    }
    return res.bodyBytes;
  }

  Future<ApiResult<dynamic>> _send(Future<http.Response> Function() call) async {
    http.Response res;
    try {
      res = await call().timeout(_timeout);
    } on TimeoutException {
      throw ApiException(
          'The server took too long to respond. Check that the API is running.');
    } catch (e) {
      throw ApiException(
          'Cannot reach the server at ${AppConfig.baseUrl}.\n'
          'Start the API, then check the address from the Server button on the login screen.');
    }

    Map<String, dynamic> body;
    try {
      body = res.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('Unexpected response from the server.',
          statusCode: res.statusCode);
    }

    final success = body['success'] == true;
    final message = (body['message'] as String?) ?? '';

    if (res.statusCode == 401) {
      await onUnauthorized?.call();
      throw ApiException(message.isEmpty ? 'Please log in again.' : message,
          statusCode: 401);
    }

    if (!success) {
      throw ApiException(
        message.isEmpty ? 'Request failed (HTTP ${res.statusCode}).' : message,
        statusCode: res.statusCode,
        errors: body['errors'] is Map<String, dynamic>
            ? body['errors'] as Map<String, dynamic>
            : null,
      );
    }

    return ApiResult(body['data'], message);
  }
}
