import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'api_config.dart';

class ApiException implements Exception {
  const ApiException(this.message, this.statusCode, [this.details]);
  final String message;
  final int statusCode;
  final Map<String, dynamic>? details;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({required this.accountEmail, http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  static const configuredBaseUrl = String.fromEnvironment('API_BASE_URL');
  final String accountEmail;
  final http.Client _http;

  String get baseUrl =>
      configuredBaseUrl.isEmpty ? defaultApiBaseUrl() : configuredBaseUrl;

  Map<String, String> get _headers => {
    'authorization': 'Bearer local-or-cognito-token',
    'x-dev-account-email': accountEmail,
    'content-type': 'application/json',
  };

  Future<Map<String, dynamic>> getMap(String path) async {
    final response = await _network(
      () => _http.get(Uri.parse('$baseUrl$path'), headers: _headers),
    );
    return _decodeMap(response);
  }

  Future<List<dynamic>> getList(String path) async {
    final response = await _network(
      () => _http.get(Uri.parse('$baseUrl$path'), headers: _headers),
    );
    _throwIfFailed(response);
    return jsonDecode(response.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> post(
    String path, [
    Map<String, Object?>? body,
  ]) async {
    final response = await _network(
      () => _http.post(
        Uri.parse('$baseUrl$path'),
        headers: _headers,
        body: jsonEncode(body ?? const <String, Object?>{}),
      ),
    );
    return _decodeMap(response);
  }

  Future<Map<String, dynamic>> patch(
    String path,
    Map<String, Object?> body,
  ) async {
    final response = await _network(
      () => _http.patch(
        Uri.parse('$baseUrl$path'),
        headers: _headers,
        body: jsonEncode(body),
      ),
    );
    return _decodeMap(response);
  }

  Future<Map<String, dynamic>> delete(String path) async {
    final response = await _network(
      () => _http.delete(Uri.parse('$baseUrl$path'), headers: _headers),
    );
    return _decodeMap(response);
  }

  Future<Map<String, dynamic>> uploadFile(
    String path, {
    required String fieldName,
    required String fileName,
    required String contentType,
    required List<int> bytes,
    Map<String, String> fields = const {},
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'))
      ..headers.addAll({
        'authorization': 'Bearer local-or-cognito-token',
        'x-dev-account-email': accountEmail,
      })
      ..fields.addAll(fields)
      ..files.add(
        http.MultipartFile.fromBytes(
          fieldName,
          bytes,
          filename: fileName,
          contentType: MediaType.parse(contentType),
        ),
      );
    final streamed = await _network(() => _http.send(request));
    final response = await _network(() => http.Response.fromStream(streamed));
    return _decodeMap(response);
  }

  /// 预签名下载地址已经带有短时授权，不能再附加账号头部。
  Future<List<int>> fetchSignedUrl(String url) async {
    final response = await _network(() => _http.get(Uri.parse(url)));
    if (response.statusCode != 200) {
      throw ApiException('下载链接已失效，请重新获取', response.statusCode);
    }
    return response.bodyBytes;
  }

  /// 预签名上传地址已经包含短时授权；不能附加账号 token，也不能记录 URL。
  Future<void> putSignedUrl(
    String url,
    List<int> bytes, {
    required Map<String, String> headers,
  }) async {
    final response = await _network(
      () => _http.put(Uri.parse(url), headers: headers, body: bytes),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('云存储暂时拒绝上传', response.statusCode);
    }
  }

  Map<String, dynamic> _decodeMap(http.Response response) {
    _throwIfFailed(response);
    if (response.body.isEmpty) return <String, dynamic>{};
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  void _throwIfFailed(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    var message = '服务暂时不可用（${response.statusCode}）';
    Map<String, dynamic>? details;
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      details = body;
      final raw = body['message'];
      message = raw is List
          ? raw.join('；')
          : raw is Map<String, dynamic>
          ? raw['message']?.toString() ?? message
          : raw?.toString() ?? message;
    } catch (_) {
      // Do not expose raw HTML or proxy errors to the user.
    }
    throw ApiException(message, response.statusCode, details);
  }

  Future<T> _network<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException('网络不可用，请稍后重试', 0);
    }
  }
}
