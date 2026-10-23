import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:invoiso_core/rpc/rpc_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the app's data lives: the invoiso server's base URL, kept in local
/// preferences (per device, not per company) so it can be changed from the
/// login screen without rebuilding. `--dart-define=API_BASE_URL=...` only
/// sets the default.
class ServerSettings {
  static const _key = 'server_base_url';

  /// Baked in by the release pipeline (repo variable API_BASE_URL); CI passes
  /// an empty value when the variable isn't set, hence the fallback.
  static const _builtBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const defaultBaseUrl =
      _builtBaseUrl == '' ? 'http://localhost:8080' : _builtBaseUrl;

  static Future<String> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key) ?? defaultBaseUrl;
  }

  static Future<void> save(String baseUrl) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, normalize(baseUrl));
  }

  /// Trims, adds `https://` when no scheme is given, drops trailing slashes.
  static String normalize(String input) {
    var url = input.trim();
    if (url.isEmpty) return url;
    if (!url.contains('://')) url = 'https://$url';
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }
}

/// A company the server hosts, as listed on the login screen.
class ServerCompany {
  ServerCompany(this.id, this.name);

  final String id;
  final String name;
}

/// Result of a successful login.
class ServerSession {
  ServerSession({
    required this.token,
    required this.expiresAt,
    required this.company,
    required this.user,
  });

  final String token;
  final DateTime expiresAt;
  final ServerCompany company;

  /// `User.toMap()` shape (password/salt blanked by the server).
  final Map<String, dynamic> user;
}

/// HTTP client for the invoiso server: the public endpoints (health,
/// companies, login) plus the [RpcClient] the generated `Http*Repository`
/// classes call. Holds the session token after [login].
class ServerConnection implements RpcClient {
  ServerConnection(this.baseUrl, {http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  String? _token;

  /// Called when the server rejects the token (expired / server restarted
  /// with a new secret), so the app can return to the login screen.
  void Function()? onUnauthorized;

  static const _timeout = Duration(seconds: 30);

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> get _headers => {
        'content-type': 'application/json',
        if (_token != null) 'authorization': 'Bearer $_token',
      };

  Future<Object?> _send(Future<http.Response> request) async {
    final http.Response res;
    try {
      res = await request.timeout(_timeout);
    } on TimeoutException {
      throw RpcException('unreachable', 'The server did not respond in time');
    } on Exception catch (e) {
      throw RpcException('unreachable', 'Cannot reach the server ($e)');
    }
    final body = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode >= 400) {
      final err = (body is Map ? body['error'] : null) as Map?;
      final code = err?['code'] as String? ?? 'http_${res.statusCode}';
      if (res.statusCode == 401 && _token != null) {
        _token = null;
        onUnauthorized?.call();
      }
      throw RpcException(code, err?['message'] as String? ?? res.reasonPhrase ?? 'Error');
    }
    return body;
  }

  /// Server version when reachable; throws [RpcException] otherwise.
  Future<String> health() async {
    final body = await _send(_client.get(_uri('/health')));
    return (body as Map)['version'] as String? ?? '?';
  }

  Future<List<ServerCompany>> companies() async {
    final body = await _send(_client.get(_uri('/companies'))) as List;
    return [
      for (final c in body.cast<Map>())
        ServerCompany(c['id'] as String, c['name'] as String),
    ];
  }

  Future<ServerSession> login(
      String companyId, String username, String password) async {
    final body = await _send(_client.post(_uri('/auth/login'),
        headers: _headers,
        body: jsonEncode(
            {'companyId': companyId, 'username': username, 'password': password}))) as Map;
    _token = body['token'] as String;
    final company = body['company'] as Map;
    return ServerSession(
      token: _token!,
      expiresAt: DateTime.parse(body['expiresAt'] as String),
      company: ServerCompany(company['id'] as String, company['name'] as String),
      user: (body['user'] as Map).cast<String, dynamic>(),
    );
  }

  // ── Admin (needs an admin session) ──

  Future<ServerCompany> createCompany(
      String name, String adminUsername, String adminPassword) async {
    final body = await _send(_client.post(_uri('/admin/companies'),
        headers: _headers,
        body: jsonEncode({
          'name': name,
          'adminUsername': adminUsername,
          'adminPassword': adminPassword,
        }))) as Map;
    return ServerCompany(body['id'] as String, body['name'] as String);
  }

  Future<void> renameCompany(String id, String name) => _send(_client.patch(
      _uri('/admin/companies/$id'),
      headers: _headers,
      body: jsonEncode({'name': name})));

  Future<void> deleteCompany(String id) =>
      _send(_client.delete(_uri('/admin/companies/$id'), headers: _headers));

  /// Uploads a desktop install's SQLite `.db` as a new company. Returns row
  /// counts per table as the server imported them.
  Future<Map<String, int>> importDatabase(String name, List<int> dbBytes) async {
    final uri = _uri('/admin/import').replace(queryParameters: {'name': name});
    final res = await _send(_client
        .post(uri,
            headers: {..._headers, 'content-type': 'application/octet-stream'},
            body: dbBytes)
        .timeout(const Duration(minutes: 5))) as Map;
    return (res['rows'] as Map).map((k, v) => MapEntry(k as String, v as int));
  }

  void logout() => _token = null;

  bool get isLoggedIn => _token != null;

  @override
  Future<Object?> call(String method, Map<String, Object?> args) async {
    final body = await _send(_client.post(_uri('/rpc/$method'),
        headers: _headers, body: jsonEncode({'args': args})));
    return (body as Map)['result'];
  }
}
