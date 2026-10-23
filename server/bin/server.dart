import 'dart:io';
import 'dart:math';

import 'package:invoiso_core/repositories/sqlite/sqlite_auth_repository.dart';
import 'package:invoiso_core/rpc/rpc_handlers.g.dart';
import 'package:invoiso_pg/invoiso_pg.dart';
import 'package:invoiso_server/invoiso_server.dart';
import 'package:postgres/postgres.dart' as pg;
import 'package:shelf/shelf_io.dart' as io;

Future<void> main() async {
  final config = ServerConfig.fromEnvironment();
  final pool = pg.Pool.withUrl(config.databaseUrl);
  final sync = await SchemaSync.load();
  final companies = CompanyStore(pool, sync);
  await companies.init();
  await _ensureFirstCompany(companies, config);

  final api = InvoisoApi(config, companies, rpcHandlers(serverRepositories()));
  final server =
      await io.serve(api.handler, InternetAddress.anyIPv4, config.port);
  stdout.writeln('invoiso server $serverVersion listening on :${server.port}');

  // Docker/Railway stop the container with SIGTERM (not available on Windows).
  final stopSignal =
      Platform.isWindows ? ProcessSignal.sigint : ProcessSignal.sigterm;
  stopSignal.watch().listen((_) async {
    await server.close();
    await pool.close();
    exit(0);
  });
}

/// First boot: create a company so the app has something to log into, and
/// replace the seeded admin/admin password (never leave that on a public
/// server).
Future<void> _ensureFirstCompany(CompanyStore companies, ServerConfig config) async {
  if ((await companies.list()).isNotEmpty) return;
  final (company, _) = await companies.create('My Company');
  final generated = config.initialAdminPassword == null;
  final password = config.initialAdminPassword ?? _randomPassword();
  await companies.inCompany(company, () async {
    final auth = SqliteAuthRepository();
    final admin = (await auth.getUserByUsername('admin'))!;
    await auth.updatePassword(admin.id, password);
    await auth.markPasswordChanged(admin.id);
  });
  stdout.writeln('Created company "${company.name}" — log in as "admin"'
      '${generated ? ' with password: $password  (shown once; change it in the app)' : ' with INITIAL_ADMIN_PASSWORD'}');
}

String _randomPassword() {
  const chars = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final rnd = Random.secure();
  return List.generate(16, (_) => chars[rnd.nextInt(chars.length)]).join();
}
