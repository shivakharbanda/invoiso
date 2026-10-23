import 'dart:convert';
import 'dart:io';

import 'package:invoiso_core/models/company_info.dart';
import 'package:invoiso_core/models/user.dart';
import 'package:invoiso_core/repositories/sqlite/sqlite_auth_repository.dart';
import 'package:invoiso_core/repositories/sqlite/sqlite_company_info_repository.dart';
import 'package:invoiso_core/rpc/rpc_handlers.g.dart';
import 'package:invoiso_pg/invoiso_pg.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'access.dart';
import 'auth.dart';
import 'companies.dart';
import 'config.dart';

const serverVersion = '0.1.0';

/// Thrown inside handlers to produce a JSON error response.
class ApiError implements Exception {
  ApiError(this.status, this.code, this.message);

  final int status;
  final String code;
  final String message;
}

Response _json(Object? body, {int status = 200}) => Response(status,
    body: jsonEncode(body), headers: {'content-type': 'application/json'});

Future<Map<String, dynamic>> _body(Request req) async {
  final text = await req.readAsString();
  if (text.isEmpty) return {};
  final decoded = jsonDecode(text);
  if (decoded is! Map<String, dynamic>) {
    throw ApiError(400, 'bad_request', 'Expected a JSON object');
  }
  return decoded;
}

/// The HTTP API:
///   GET  /health                      liveness (no auth)
///   GET  /companies                   [{id, name}] for the login picker
///   POST /auth/login                  {companyId, username, password} → token
///   GET  /auth/me                     current user
///   POST /rpc/<repo>.<method>         {args: {...}} → {result}
///   POST /admin/companies             {name} → new company (admin)
///   PATCH/DELETE /admin/companies/<id>            (admin)
///   POST /admin/import?name=…         body: an invoiso .db file (admin)
class InvoisoApi {
  InvoisoApi(this._config, this._companies, this._handlers);

  final ServerConfig _config;
  final CompanyStore _companies;
  final Map<String, RpcHandler> _handlers;
  late final _tokens = TokenSigner(_config.tokenSecret);
  final _throttle = LoginThrottle();

  Handler get handler {
    final router = Router()
      ..get('/health', (_) => _json({'status': 'ok', 'version': serverVersion}))
      ..get('/companies', _listCompanies)
      ..post('/auth/login', _login)
      ..get('/auth/me', _me)
      ..post('/rpc/<method>', _rpc)
      ..post('/admin/companies', _createCompany)
      ..patch('/admin/companies/<id>', _renameCompany)
      ..delete('/admin/companies/<id>', _deleteCompany)
      ..post('/admin/import', _import);
    return const Pipeline()
        .addMiddleware(_errors)
        .addHandler(router.call);
  }

  Handler _errors(Handler inner) => (req) async {
        try {
          return await inner(req);
        } on ApiError catch (e) {
          return _json({'error': {'code': e.code, 'message': e.message}},
              status: e.status);
        } on FormatException catch (e) {
          return _json({'error': {'code': 'bad_request', 'message': e.message}},
              status: 400);
        } catch (e, st) {
          stderr.writeln('[${req.method} ${req.requestedUri.path}] $e\n$st');
          return _json(
              {'error': {'code': 'failed', 'message': 'Internal server error'}},
              status: 500);
        }
      };

  Session _session(Request req) {
    final header = req.headers['authorization'] ?? '';
    final token = header.startsWith('Bearer ') ? header.substring(7) : '';
    final s = _tokens.verify(token);
    if (s == null) throw ApiError(401, 'unauthorized', 'Log in again');
    return s;
  }

  Future<Company> _company(String id) async =>
      await _companies.byId(id) ??
      (throw ApiError(404, 'not_found', 'Unknown company'));

  Future<Response> _listCompanies(Request req) async =>
      _json([for (final c in await _companies.list()) c.toJson()]);

  Future<Response> _login(Request req) async {
    final body = await _body(req);
    final companyId = body['companyId'] as String? ?? '';
    final username = (body['username'] as String? ?? '').trim();
    final password = body['password'] as String? ?? '';
    final ip = (req.context['shelf.io.connection_info'] as HttpConnectionInfo?)
            ?.remoteAddress
            .address ??
        '?';
    final key = '$ip|$companyId|${username.toLowerCase()}';
    if (_throttle.isBlocked(key)) {
      throw ApiError(429, 'too_many_attempts',
          'Too many failed logins. Try again in 15 minutes.');
    }
    final company = await _company(companyId);
    final user = await _companies.inCompany(
        company, () => SqliteAuthRepository().getUser(username, password));
    if (user == null) {
      _throttle.recordFailure(key);
      throw ApiError(401, 'invalid_credentials', 'Wrong username or password');
    }
    _throttle.reset(key);
    final session = Session(
      companyId: company.id,
      userId: user.id,
      isAdmin: user.isAdmin(),
      expiresAt: DateTime.now().add(_config.tokenTtl),
    );
    return _json({
      'token': _tokens.issue(session),
      'expiresAt': session.expiresAt.toUtc().toIso8601String(),
      'company': company.toJson(),
      'user': AccessPolicy.redact('auth.', user.toMap()),
    });
  }

  Future<Response> _me(Request req) async {
    final s = _session(req);
    final company = await _company(s.companyId);
    final user = await _companies.inCompany(
        company, () => SqliteAuthRepository().getUserById(s.userId));
    if (user == null) throw ApiError(401, 'unauthorized', 'User no longer exists');
    return _json({
      'company': company.toJson(),
      'user': AccessPolicy.redact('auth.', user.toMap()),
    });
  }

  Future<Response> _rpc(Request req, String method) async {
    final s = _session(req);
    final handler = _handlers[method] ??
        (throw ApiError(404, 'not_found', 'Unknown method $method'));
    final args = ((await _body(req))['args'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final denied = AccessPolicy.check(method, s, args);
    if (denied != null) throw ApiError(403, 'forbidden', denied);
    final company = await _company(s.companyId);
    final result = await _companies.inCompany(company, () => handler(args));
    return _json({'result': AccessPolicy.redact(method, result)});
  }

  Session _admin(Request req) {
    final s = _session(req);
    if (!s.isAdmin) throw ApiError(403, 'forbidden', 'admin only');
    return s;
  }

  /// Body: {name, adminUsername, adminPassword}. The new company's seeded
  /// admin/admin login is replaced with these before anyone can use it.
  Future<Response> _createCompany(Request req) async {
    _admin(req);
    final body = await _body(req);
    final name = (body['name'] as String? ?? '').trim();
    final username = (body['adminUsername'] as String? ?? '').trim();
    final password = body['adminPassword'] as String? ?? '';
    if (name.isEmpty || username.isEmpty || password.length < 6) {
      throw ApiError(400, 'bad_request',
          'name, adminUsername and adminPassword (6+ characters) are required');
    }
    final (company, _) = await _companies.create(name);
    await _companies.inCompany(company, () async {
      final auth = SqliteAuthRepository();
      final admin = (await auth.getUserByUsername('admin'))!;
      await auth.updateUser(User(
          id: admin.id, username: username, password: '', userType: admin.userType));
      await auth.updatePassword(admin.id, password);
      await auth.markPasswordChanged(admin.id);
      final companyInfo = SqliteCompanyInfoRepository();
      final info = await companyInfo.getCompanyInfo();
      if (info != null) {
        await companyInfo.updateCompanyInfo(CompanyInfo(
          id: info.id,
          name: name,
          address: info.address,
          phone: info.phone,
          email: info.email,
          website: info.website,
          gstin: info.gstin,
          panNumber: info.panNumber,
          fssaiCode: info.fssaiCode,
          country: info.country,
        ));
      }
    });
    return _json(company.toJson(), status: 201);
  }

  Future<Response> _renameCompany(Request req, String id) async {
    _admin(req);
    final name = ((await _body(req))['name'] as String? ?? '').trim();
    if (name.isEmpty) throw ApiError(400, 'bad_request', 'name is required');
    await _company(id);
    await _companies.rename(id, name);
    return _json({'id': id, 'name': name});
  }

  Future<Response> _deleteCompany(Request req, String id) async {
    final s = _admin(req);
    if (s.companyId == id) {
      throw ApiError(400, 'bad_request', 'Switch to another company first');
    }
    await _company(id);
    await _companies.delete(id);
    return Response(204);
  }

  /// One-time migration of a desktop install: the body is the company's
  /// SQLite `.db` file. It's upgraded with the app's own migrations, then
  /// copied into a new company. Responds with per-table row counts.
  Future<Response> _import(Request req) async {
    _admin(req);
    final name = (req.url.queryParameters['name'] ?? '').trim();
    if (name.isEmpty) throw ApiError(400, 'bad_request', 'name is required');
    final dir = await Directory.systemTemp.createTemp('invoiso_import');
    try {
      final file = File('${dir.path}/upload.db');
      final sink = file.openWrite();
      var size = 0;
      await for (final chunk in req.read()) {
        size += chunk.length;
        if (size > 500 * 1024 * 1024) {
          throw ApiError(413, 'too_large', 'Database file over 500 MB');
        }
        sink.add(chunk);
      }
      await sink.close();
      final sqlite = await SchemaSync.openUpgradedSqlite(file.path);
      try {
        final (company, counts) =
            await _companies.create(name, fromSqlite: sqlite);
        return _json({'company': company.toJson(), 'rows': counts}, status: 201);
      } finally {
        await sqlite.close();
      }
    } finally {
      await dir.delete(recursive: true);
    }
  }
}
