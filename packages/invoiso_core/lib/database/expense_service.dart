import 'dart:convert';

import 'package:invoiso_core/models/expense.dart';
import 'package:invoiso_core/utils/app_date.dart';
import 'package:invoiso_core/utils/app_logger.dart';
import 'package:sqflite_common/sqflite.dart';
import 'package:sqflite_common/utils/utils.dart';
import 'package:uuid/uuid.dart';

import 'database_helper.dart';

const _tag = 'ExpenseService';

/// Vendor spend: expenses, their categories, projects, receipts and
/// recurring templates. Vendors themselves are suppliers (SupplierService).
class ExpenseService {
  static final _dbHelper = DatabaseHelper();
  static const _uuid = Uuid();

  /// Receipts are stored in the database; keep them reasonably small.
  static const maxAttachmentBytes = 10 * 1024 * 1024;

  // ── Categories ─────────────────────────────────────────────────────────

  /// Seeds [ExpenseCategory.defaults] the first time a company reads its
  /// categories (covers fresh installs, migrated databases and companies
  /// created on the server alike).
  static Future<List<ExpenseCategory>> getCategories() async {
    final db = await _dbHelper.database;
    var rows = await db.query('expense_categories',
        where: 'deleted_at IS NULL', orderBy: 'sort_order, name');
    if (rows.isEmpty) {
      final any = firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM expense_categories'));
      if ((any ?? 0) == 0) {
        final batch = db.batch();
        for (final c in ExpenseCategory.defaults) {
          batch.insert('expense_categories', c.toMap());
        }
        await batch.commit(noResult: true);
        rows = await db.query('expense_categories',
            where: 'deleted_at IS NULL', orderBy: 'sort_order, name');
      }
    }
    return rows.map(ExpenseCategory.fromMap).toList();
  }

  static Future<void> saveCategory(ExpenseCategory category) async {
    final db = await _dbHelper.database;
    await db.insert('expense_categories', category.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Soft delete: existing expenses keep pointing at it.
  static Future<void> deleteCategory(String id) async {
    final db = await _dbHelper.database;
    await db.update('expense_categories',
        {'deleted_at': DateTime.now().toIso8601String()},
        where: 'id = ?', whereArgs: [id]);
  }

  // ── Projects ───────────────────────────────────────────────────────────

  static Future<List<Project>> getProjects({bool includeArchived = false}) async {
    final db = await _dbHelper.database;
    final rows = await db.query('projects',
        where: includeArchived ? null : 'archived = 0', orderBy: 'name');
    return rows.map(Project.fromMap).toList();
  }

  static Future<void> saveProject(Project project) async {
    final db = await _dbHelper.database;
    final updated = await db.update('projects', project.toMap()..remove('id'),
        where: 'id = ?', whereArgs: [project.id]);
    if (updated == 0) {
      await db.insert('projects',
          {...project.toMap(), 'created_at': DateTime.now().toIso8601String()});
    }
  }

  // ── Expenses ───────────────────────────────────────────────────────────

  static (String, List<Object?>) _where(ExpenseFilter f, {String alias = ''}) {
    final a = alias.isEmpty ? '' : '$alias.';
    final parts = <String>['${a}deleted_at IS NULL'];
    final args = <Object?>[];
    void eq(String col, String? value) {
      if (value != null && value.isNotEmpty) {
        parts.add('$a$col = ?');
        args.add(value);
      }
    }

    if (f.from != null) {
      parts.add('${a}date >= ?');
      args.add(AppDate.dateKeyStart(f.from!));
    }
    if (f.to != null) {
      parts.add('${a}date <= ?');
      args.add(AppDate.dateKeyEnd(f.to!));
    }
    eq('vendor_id', f.vendorId);
    eq('category_id', f.categoryId);
    eq('entry_type', f.entryType);
    eq('customer_id', f.customerId);
    eq('project_id', f.projectId);
    final q = f.search.trim();
    if (q.isNotEmpty) {
      parts.add('(${a}vendor_name LIKE ? OR ${a}description LIKE ? '
          'OR ${a}reference_no LIKE ? OR ${a}notes LIKE ?)');
      args.addAll(List.filled(4, '%$q%'));
    }
    return (parts.join(' AND '), args);
  }

  static Future<List<Expense>> getExpenses(ExpenseFilter filter,
      {int limit = 200, int offset = 0}) async {
    final db = await _dbHelper.database;
    final (where, args) = _where(filter, alias: 'e');
    final rows = await db.rawQuery(
      'SELECT e.*, (SELECT COUNT(*) FROM expense_attachments x '
      'WHERE x.expense_id = e.id) AS attachment_count '
      'FROM expenses e WHERE $where '
      'ORDER BY e.date DESC, e.created_at DESC, e.id '
      'LIMIT ? OFFSET ?',
      [...args, limit, offset],
    );
    return rows.map(Expense.fromMap).toList();
  }

  static Future<int> countExpenses(ExpenseFilter filter) async {
    final db = await _dbHelper.database;
    final (where, args) = _where(filter);
    return firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM expenses WHERE $where', args)) ??
        0;
  }

  static Future<Expense?> getExpense(String id) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery(
      'SELECT e.*, (SELECT COUNT(*) FROM expense_attachments x '
      'WHERE x.expense_id = e.id) AS attachment_count '
      'FROM expenses e WHERE e.id = ?',
      [id],
    );
    return rows.isEmpty ? null : Expense.fromMap(rows.first);
  }

  /// Insert or update by id. Returns the saved id.
  static Future<String> saveExpense(Expense expense) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toIso8601String();
    final row = expense.toMap()..['updated_at'] = now;
    final updated = await db.update('expenses',
        Map.of(row)..remove('id')..remove('created_at'),
        where: 'id = ?', whereArgs: [expense.id]);
    if (updated == 0) {
      row['created_at'] = expense.createdAt?.toIso8601String() ?? now;
      await db.insert('expenses', row);
    }
    AppLogger.d(_tag, 'Saved expense ${expense.id} (${expense.entryType})');
    return expense.id;
  }

  /// Soft delete (receipts kept until the row is purged).
  static Future<void> deleteExpense(String id) async {
    final db = await _dbHelper.database;
    await db.update('expenses', {'deleted_at': DateTime.now().toIso8601String()},
        where: 'id = ?', whereArgs: [id]);
  }

  // ── Receipts ───────────────────────────────────────────────────────────

  static Future<List<ExpenseAttachment>> getAttachments(String expenseId) async {
    final db = await _dbHelper.database;
    final rows = await db.query('expense_attachments',
        columns: ['id', 'expense_id', 'file_name', 'mime_type', 'size', 'created_at'],
        where: 'expense_id = ?',
        whereArgs: [expenseId],
        orderBy: 'created_at');
    return rows.map(ExpenseAttachment.fromMap).toList();
  }

  /// [dataBase64] is the file content, base64-encoded (keeps the API JSON).
  static Future<ExpenseAttachment> addAttachment(String expenseId,
      String fileName, String mimeType, String dataBase64) async {
    final bytes = base64Decode(dataBase64);
    if (bytes.length > maxAttachmentBytes) {
      throw ArgumentError('Receipt is larger than 10 MB');
    }
    final attachment = ExpenseAttachment(
      id: _uuid.v4(),
      expenseId: expenseId,
      fileName: fileName,
      mimeType: mimeType,
      size: bytes.length,
      createdAt: DateTime.now(),
    );
    final db = await _dbHelper.database;
    await db.insert('expense_attachments', {...attachment.toMap(), 'data': bytes});
    return attachment;
  }

  /// Base64 file content, or null if the attachment no longer exists.
  static Future<String?> getAttachmentData(String id) async {
    final db = await _dbHelper.database;
    final rows = await db.query('expense_attachments',
        columns: ['data'], where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty || rows.first['data'] == null) return null;
    return base64Encode(rows.first['data'] as List<int>);
  }

  static Future<void> deleteAttachment(String id) async {
    final db = await _dbHelper.database;
    await db.delete('expense_attachments', where: 'id = ?', whereArgs: [id]);
  }

  // ── Recurring templates ────────────────────────────────────────────────

  static Future<List<RecurringExpense>> getRecurring() async {
    final db = await _dbHelper.database;
    final rows =
        await db.query('recurring_expenses', orderBy: 'active DESC, next_due');
    return rows.map(RecurringExpense.fromMap).toList();
  }

  static Future<void> saveRecurring(RecurringExpense r) async {
    final db = await _dbHelper.database;
    final updated = await db.update('recurring_expenses', r.toMap()..remove('id'),
        where: 'id = ?', whereArgs: [r.id]);
    if (updated == 0) {
      await db.insert('recurring_expenses',
          {...r.toMap(), 'created_at': DateTime.now().toIso8601String()});
    }
  }

  static Future<void> deleteRecurring(String id) async {
    final db = await _dbHelper.database;
    await db.delete('recurring_expenses', where: 'id = ?', whereArgs: [id]);
  }

  /// Active templates due on or before [asOf].
  static Future<List<RecurringExpense>> getDueRecurring(DateTime asOf) async {
    final db = await _dbHelper.database;
    final rows = await db.query('recurring_expenses',
        where: 'active = 1 AND next_due <= ?',
        whereArgs: [AppDate.dateKeyEnd(asOf)],
        orderBy: 'next_due');
    return rows.map(RecurringExpense.fromMap).toList();
  }

  /// Saves [expense] (the user-confirmed occurrence of template [recurringId])
  /// and moves the template's next due date one period forward.
  static Future<void> recordRecurring(String recurringId, Expense expense) async {
    final db = await _dbHelper.database;
    final rows = await db.query('recurring_expenses',
        where: 'id = ?', whereArgs: [recurringId]);
    if (rows.isEmpty) throw ArgumentError('Unknown recurring expense');
    final template = RecurringExpense.fromMap(rows.first);
    await saveExpense(Expense.fromMap(
        {...expense.toMap(), 'recurring_id': recurringId}));
    await db.update('recurring_expenses',
        {'next_due': template.followingDue.toIso8601String()},
        where: 'id = ?', whereArgs: [recurringId]);
  }
}
