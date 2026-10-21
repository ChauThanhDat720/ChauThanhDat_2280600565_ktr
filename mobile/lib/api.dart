import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

typedef Json = Map<String, dynamic>;

class ApiException implements Exception {
  final String message;
  final int status;
  ApiException(this.message, [this.status = 0]);
  @override
  String toString() => message;
}

class Api extends ChangeNotifier {
  static const baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://10.0.2.2:5099',
  );
  final http.Client client;
  final FlutterSecureStorage storage;
  String? token;
  Json? user;
  bool restored = false;
  Api({http.Client? client, FlutterSecureStorage? storage})
    : client = client ?? http.Client(),
      storage = storage ?? const FlutterSecureStorage();
  Future<dynamic> request(String method, String path, [Json? body]) async {
    try {
      final req = http.Request(method, Uri.parse('$baseUrl/api$path'));
      req.headers['Content-Type'] = 'application/json';
      if (token != null) req.headers['Authorization'] = 'Bearer $token';
      if (body != null) req.body = jsonEncode(body);
      final res = await (() async => http.Response.fromStream(
        await client.send(req),
      ))().timeout(const Duration(seconds: 25));
      dynamic data;
      if (res.body.isNotEmpty) {
        try {
          data = jsonDecode(utf8.decode(res.bodyBytes));
        } catch (_) {
          data = null;
        }
      }
      if (res.statusCode >= 400) {
        if (res.statusCode == 401 && token != null) {
          token = null;
          user = null;
          await storage.delete(key: 'session');
          notifyListeners();
        }
        throw ApiException(
          data is Map
              ? data['message']?.toString() ?? 'Yêu cầu bị từ chối.'
              : res.statusCode == 403
              ? 'Bạn không có quyền thực hiện thao tác này.'
              : 'Yêu cầu thất bại (${res.statusCode}).',
          res.statusCode,
        );
      }
      return data;
    } on TimeoutException {
      throw ApiException('Kết nối quá thời gian. Hãy kiểm tra máy chủ.');
    } on SocketException {
      throw ApiException(
        'Không kết nối được máy chủ. Kiểm tra mạng và API_URL.',
      );
    } on http.ClientException {
      throw ApiException('Mất kết nối đến máy chủ. Vui lòng thử lại.');
    } on FormatException {
      throw ApiException('Dữ liệu từ máy chủ không đúng định dạng.');
    }
  }

  Future<List<Json>> list(String path) async =>
      (await request('GET', path) as List).cast<Json>();
  Future<void> restore() async {
    try {
      token = await storage.read(key: 'session');
      if (token != null) user = await request('GET', '/auth/me') as Json;
    } catch (_) {
      token = null;
      user = null;
      try {
        await storage.delete(key: 'session');
      } catch (_) {}
    }
    restored = true;
    notifyListeners();
  }

  Future<void> verify(String challenge, String code) async {
    final result = await request('POST', '/auth/verify', {
      'challengeId': challenge,
      'code': code,
    }) as Json;
    await acceptSession(result);
  }

  Future<void> acceptSession(Json result) async {
    await storage.write(key: 'session', value: result['token'] as String);
    token = result['token'] as String;
    user = result['user'] as Json;
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      if (token != null) await request('POST', '/auth/logout');
    } finally {
      await storage.delete(key: 'session');
      token = null;
      user = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    client.close();
    super.dispose();
  }
}
