import 'dart:typed_data';

import 'package:postgres/postgres.dart' as pg;
import 'package:sqflite_common/sqlite_api.dart';

import 'sql_translate.dart';

/// Primary-key columns per table, read once from the catalog by
/// `SchemaSync.loadCatalog` — needed to emulate `ConflictAlgorithm.replace`.
class PgCatalog {
  PgCatalog(this.primaryKeys);

  final Map<String, List<String>> primaryKeys;
}

const _numericOid = 1700;

/// sqflite's [DatabaseExecutor] on top of a Postgres session, so the existing
/// invoiso_core services run unchanged. The session's `search_path` must
/// already point at the company schema (see `PgDatabase.open`).
class PgExecutor implements DatabaseExecutor {
  PgExecutor(this._session, this._catalog, this._owner);

  final pg.Session _session;
  final PgCatalog _catalog;
  final PgDatabase? _owner;

  @override
  Database get database => _owner ?? (throw StateError('No owning database'));

  Future<pg.Result> _run(String sql, List<Object?>? arguments) {
    return _session.execute(
      translateSql(sql),
      parameters: (arguments ?? const []).map(_param).toList(),
    );
  }

  static Object? _param(Object? v) {
    if (v is bool) return v ? 1 : 0;
    if (v is List<int>) return pg.TypedValue(pg.Type.byteArray, v);
    return v;
  }

  /// Rows as sqflite returns them. Postgres `numeric` (e.g. SUM over bigint)
  /// comes back as text from the driver; SQLite would give int/double. The
  /// synthetic `rowid` column is hidden unless the statement asked for it.
  static List<Map<String, Object?>> _rows(pg.Result result, String sql) {
    final cols = result.schema.columns;
    final keepRowid = RegExp(r'\browid\b', caseSensitive: false).hasMatch(sql);
    return [
      for (final row in result)
        {
          for (var i = 0; i < cols.length; i++)
            if (keepRowid || cols[i].columnName != 'rowid')
              cols[i].columnName ?? '?column?': _value(row[i], cols[i].typeOid),
        },
    ];
  }

  static Object? _value(Object? v, int oid) {
    if (v == null) return null;
    // SQLite has no boolean type; comparisons come back as 0/1.
    if (v is bool) return v ? 1 : 0;
    if (oid == _numericOid) {
      final s = v.toString();
      return s.contains('.') ? double.parse(s) : int.parse(s);
    }
    if (v is List<int> && v is! Uint8List) return Uint8List.fromList(v);
    return v;
  }

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    await _run(sql, arguments);
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql,
      [List<Object?>? arguments]) async {
    return _rows(await _run(sql, arguments), sql);
  }

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) async {
    final result = await _run('$sql RETURNING rowid', arguments);
    return result.isEmpty ? 0 : (result.first.first as int? ?? 0);
  }

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) async =>
      (await _run(sql, arguments)).affectedRows;

  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) async =>
      (await _run(sql, arguments)).affectedRows;

  @override
  Future<int> insert(String table, Map<String, Object?> values,
      {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) {
    final b = _insertSql(table, values, conflictAlgorithm);
    return rawInsert(b.sql, b.args);
  }

  ({String sql, List<Object?> args}) _insertSql(String table,
      Map<String, Object?> values, ConflictAlgorithm? conflict) {
    final cols = values.keys.toList();
    final sql = StringBuffer('INSERT INTO $table (${cols.join(', ')}) '
        'VALUES (${List.filled(cols.length, '?').join(', ')})');
    if (conflict == ConflictAlgorithm.ignore) {
      sql.write(' ON CONFLICT DO NOTHING');
    } else if (conflict == ConflictAlgorithm.replace) {
      final pk = _catalog.primaryKeys[table];
      if (pk == null || pk.isEmpty) {
        throw UnsupportedError('REPLACE on $table needs a primary key');
      }
      final updates = cols.where((c) => !pk.contains(c));
      sql.write(' ON CONFLICT (${pk.join(', ')}) ');
      sql.write(updates.isEmpty
          ? 'DO NOTHING'
          : 'DO UPDATE SET ${updates.map((c) => '$c = EXCLUDED.$c').join(', ')}');
    } else if (conflict != null && conflict != ConflictAlgorithm.abort &&
        conflict != ConflictAlgorithm.fail) {
      throw UnsupportedError('ConflictAlgorithm $conflict on Postgres');
    }
    return (sql: sql.toString(), args: values.values.toList());
  }

  @override
  Future<List<Map<String, Object?>>> query(String table,
      {bool? distinct,
      List<String>? columns,
      String? where,
      List<Object?>? whereArgs,
      String? groupBy,
      String? having,
      String? orderBy,
      int? limit,
      int? offset}) {
    return rawQuery(
        _querySql(table, distinct, columns, where, groupBy, having, orderBy,
            limit, offset),
        whereArgs);
  }

  static String _querySql(
      String table,
      bool? distinct,
      List<String>? columns,
      String? where,
      String? groupBy,
      String? having,
      String? orderBy,
      int? limit,
      int? offset) {
    final sql = StringBuffer('SELECT ');
    if (distinct == true) sql.write('DISTINCT ');
    sql.write(columns == null || columns.isEmpty ? '*' : columns.join(', '));
    sql.write(' FROM $table');
    if (where != null && where.isNotEmpty) sql.write(' WHERE $where');
    if (groupBy != null && groupBy.isNotEmpty) sql.write(' GROUP BY $groupBy');
    if (having != null && having.isNotEmpty) sql.write(' HAVING $having');
    if (orderBy != null && orderBy.isNotEmpty) sql.write(' ORDER BY $orderBy');
    if (limit != null) sql.write(' LIMIT $limit');
    if (offset != null) sql.write(' OFFSET $offset');
    return sql.toString();
  }

  @override
  Future<int> update(String table, Map<String, Object?> values,
      {String? where,
      List<Object?>? whereArgs,
      ConflictAlgorithm? conflictAlgorithm}) {
    final b = _updateSql(table, values, where, whereArgs);
    return rawUpdate(b.sql, b.args);
  }

  static ({String sql, List<Object?> args}) _updateSql(String table,
      Map<String, Object?> values, String? where, List<Object?>? whereArgs) {
    final sets = values.keys.map((c) => '$c = ?').join(', ');
    final sql = 'UPDATE $table SET $sets'
        '${where != null && where.isNotEmpty ? ' WHERE $where' : ''}';
    return (sql: sql, args: [...values.values, ...?whereArgs]);
  }

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) {
    return rawDelete(
        'DELETE FROM $table'
        '${where != null && where.isNotEmpty ? ' WHERE $where' : ''}',
        whereArgs);
  }

  @override
  Batch batch() => PgBatch(this);

  @override
  Future<QueryCursor> rawQueryCursor(String sql, List<Object?>? arguments,
          {int? bufferSize}) async =>
      _ListCursor(await rawQuery(sql, arguments));

  @override
  Future<QueryCursor> queryCursor(String table,
          {bool? distinct,
          List<String>? columns,
          String? where,
          List<Object?>? whereArgs,
          String? groupBy,
          String? having,
          String? orderBy,
          int? limit,
          int? offset,
          int? bufferSize}) async =>
      _ListCursor(await query(table,
          distinct: distinct,
          columns: columns,
          where: where,
          whereArgs: whereArgs,
          groupBy: groupBy,
          having: having,
          orderBy: orderBy,
          limit: limit,
          offset: offset));
}

class _PgTransaction extends PgExecutor implements Transaction {
  _PgTransaction(super.session, super.catalog, super.owner);
}

/// A company-scoped database: one pooled connection whose `search_path` is
/// set to the company schema for the lifetime of this object.
class PgDatabase extends PgExecutor implements Database {
  PgDatabase._(this._connection, PgCatalog catalog, this.path)
      : super(_connection, catalog, null);

  final pg.Connection _connection;

  @override
  final String path;

  bool _open = true;

  /// [connection] must be dedicated to this object until [close]; the caller
  /// (e.g. a request scope holding a pool connection) owns its lifetime.
  static Future<PgDatabase> open(
      pg.Connection connection, PgCatalog catalog, String schema) async {
    // `public` holds shared helpers such as safe_int (see SchemaSync).
    await connection.execute('SET search_path TO "$schema", public');
    return PgDatabase._(connection, catalog, 'postgres:$schema');
  }

  @override
  Database get database => this;

  @override
  bool get isOpen => _open;

  @override
  Future<void> close() async => _open = false;

  @override
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action,
      {bool? exclusive}) {
    return _connection
        .runTx((tx) => action(_PgTransaction(tx, _catalog, this)));
  }

  @override
  Future<T> readTransaction<T>(Future<T> Function(Transaction txn) action) =>
      transaction(action);

  @override
  Future<T> devInvokeMethod<T>(String method, [Object? arguments]) =>
      throw UnsupportedError('devInvokeMethod');

  @override
  Future<T> devInvokeSqlMethod<T>(String method, String sql,
          [List<Object?>? arguments]) =>
      throw UnsupportedError('devInvokeSqlMethod');
}

/// sqflite batches run sequentially; inside a transaction when committed from
/// a [PgDatabase], directly when applied/committed on a transaction.
class PgBatch implements Batch {
  PgBatch(this._executor);

  final PgExecutor _executor;
  final _ops = <Future<Object?> Function(PgExecutor e)>[];

  @override
  int get length => _ops.length;

  Future<List<Object?>> _runAll(PgExecutor e, bool continueOnError) async {
    final results = <Object?>[];
    for (final op in _ops) {
      try {
        results.add(await op(e));
      } catch (err) {
        if (!continueOnError) rethrow;
        results.add(err);
      }
    }
    return results;
  }

  @override
  Future<List<Object?>> commit(
      {bool? exclusive, bool? noResult, bool? continueOnError}) async {
    final ex = _executor;
    final results = ex is PgDatabase
        ? await ex.transaction(
            (txn) => _runAll(txn as PgExecutor, continueOnError ?? false))
        : await _runAll(ex, continueOnError ?? false);
    return noResult == true ? const [] : results;
  }

  @override
  Future<List<Object?>> apply({bool? noResult, bool? continueOnError}) async {
    final results = await _runAll(_executor, continueOnError ?? false);
    return noResult == true ? const [] : results;
  }

  @override
  void rawInsert(String sql, [List<Object?>? arguments]) =>
      _ops.add((e) => e.rawInsert(sql, arguments));

  @override
  void insert(String table, Map<String, Object?> values,
          {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) =>
      _ops.add((e) =>
          e.insert(table, values, conflictAlgorithm: conflictAlgorithm));

  @override
  void rawUpdate(String sql, [List<Object?>? arguments]) =>
      _ops.add((e) => e.rawUpdate(sql, arguments));

  @override
  void update(String table, Map<String, Object?> values,
          {String? where,
          List<Object?>? whereArgs,
          ConflictAlgorithm? conflictAlgorithm}) =>
      _ops.add((e) => e.update(table, values,
          where: where, whereArgs: whereArgs));

  @override
  void rawDelete(String sql, [List<Object?>? arguments]) =>
      _ops.add((e) => e.rawDelete(sql, arguments));

  @override
  void delete(String table, {String? where, List<Object?>? whereArgs}) =>
      _ops.add((e) => e.delete(table, where: where, whereArgs: whereArgs));

  @override
  void execute(String sql, [List<Object?>? arguments]) =>
      _ops.add((e) async {
        await e.execute(sql, arguments);
        return null;
      });

  @override
  void query(String table,
          {bool? distinct,
          List<String>? columns,
          String? where,
          List<Object?>? whereArgs,
          String? groupBy,
          String? having,
          String? orderBy,
          int? limit,
          int? offset}) =>
      _ops.add((e) => e.query(table,
          distinct: distinct,
          columns: columns,
          where: where,
          whereArgs: whereArgs,
          groupBy: groupBy,
          having: having,
          orderBy: orderBy,
          limit: limit,
          offset: offset));

  @override
  void rawQuery(String sql, [List<Object?>? arguments]) =>
      _ops.add((e) => e.rawQuery(sql, arguments));
}

class _ListCursor implements QueryCursor {
  _ListCursor(this._rows);

  final List<Map<String, Object?>> _rows;
  int _i = -1;

  @override
  Future<bool> moveNext() async => ++_i < _rows.length;

  @override
  Map<String, Object?> get current => _rows[_i];

  @override
  Future<void> close() async {}
}
