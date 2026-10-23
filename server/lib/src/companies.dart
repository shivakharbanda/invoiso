import 'dart:async';
import 'dart:math';

import 'package:invoiso_core/database/database_helper.dart';
import 'package:invoiso_pg/invoiso_pg.dart';
import 'package:postgres/postgres.dart' as pg;
import 'package:sqflite_common/sqlite_api.dart';

class Company {
  Company(this.id, this.name, this.schema);

  final String id;
  final String name;
  final String schema;

  Map<String, Object?> toJson() => {'id': id, 'name': name};
}

const _dbZoneKey = #invoisoCompanyDb;

/// Companies live in `public.companies`; each one's data in its own schema.
/// [inCompany] runs code with the services pointed at a company's schema.
class CompanyStore {
  CompanyStore(this._pool, this._sync);

  final pg.Pool _pool;
  final SchemaSync _sync;

  /// Creates the registry table, routes the core services to the request
  /// zone's database, and brings every company schema up to date.
  Future<void> init() async {
    await _pool.execute('''
      CREATE TABLE IF NOT EXISTS public.companies (
        id         text PRIMARY KEY,
        name       text NOT NULL,
        schema     text NOT NULL UNIQUE,
        created_at text NOT NULL,
        deleted_at text
      )''');
    DatabaseHelper.databaseOverride = () async =>
        Zone.current[_dbZoneKey] as Database? ??
        (throw StateError('No company in scope for this database call'));
    for (final c in await list()) {
      await _pool.withConnection((conn) => _sync.sync(conn, c.schema));
    }
  }

  Future<List<Company>> list() async {
    final rows = await _pool.execute(
        'SELECT id, name, schema FROM public.companies '
        'WHERE deleted_at IS NULL ORDER BY created_at');
    return [for (final r in rows) Company(r[0] as String, r[1] as String, r[2] as String)];
  }

  Future<Company?> byId(String id) async {
    final rows = await _pool.execute(
        r'SELECT id, name, schema FROM public.companies '
        r'WHERE id = $1 AND deleted_at IS NULL',
        parameters: [id]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return Company(r[0] as String, r[1] as String, r[2] as String);
  }

  static String _newId() {
    final rnd = Random.secure();
    return List.generate(12, (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[rnd.nextInt(36)])
        .join();
  }

  /// New company with the same seed data as a fresh desktop install, or —
  /// when [fromSqlite] is given — with that database's data instead.
  /// Returns the company and, for imports, row counts per table.
  Future<(Company, Map<String, int>)> create(String name,
      {Database? fromSqlite}) async {
    final id = _newId();
    final schema = SchemaSync.schemaName(id);
    final counts = await _pool.withConnection((conn) => conn.runTx((tx) async {
          late Map<String, int> counts;
          if (fromSqlite == null) {
            await _sync.createCompany(tx, schema);
            counts = const {};
          } else {
            await _sync.sync(tx, schema);
            counts = await _sync.copyFromSqlite(fromSqlite, tx, schema);
          }
          await tx.execute(
              r'INSERT INTO public.companies (id, name, schema, created_at) '
              r'VALUES ($1, $2, $3, $4)',
              parameters: [id, name, schema, DateTime.now().toUtc().toIso8601String()]);
          return counts;
        }));
    return (Company(id, name, schema), counts);
  }

  Future<void> rename(String id, String name) => _pool.execute(
      r'UPDATE public.companies SET name = $2 WHERE id = $1',
      parameters: [id, name]);

  /// Soft delete: hidden from the API, data kept (drop the schema by hand).
  Future<void> delete(String id) => _pool.execute(
      r'UPDATE public.companies SET deleted_at = $2 WHERE id = $1',
      parameters: [id, DateTime.now().toUtc().toIso8601String()]);

  /// Runs [fn] with the core services bound to [company]'s schema on one
  /// pooled connection.
  Future<T> inCompany<T>(Company company, Future<T> Function() fn) {
    return _pool.withConnection((conn) async {
      final db = await PgDatabase.open(conn, _sync.catalog, company.schema);
      return runZoned(fn, zoneValues: {_dbZoneKey: db});
    });
  }
}
