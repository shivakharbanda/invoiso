import 'package:invoiso_core/models/expense.dart';

abstract class ExpenseRepository {
  Future<List<ExpenseCategory>> getCategories();
  Future<void> saveCategory(ExpenseCategory category);
  Future<void> deleteCategory(String id);

  Future<List<Project>> getProjects({bool includeArchived = false});
  Future<void> saveProject(Project project);

  Future<List<Expense>> getExpenses(ExpenseFilter filter,
      {int limit = 200, int offset = 0});
  Future<int> countExpenses(ExpenseFilter filter);
  Future<Expense?> getExpense(String id);

  /// Insert or update by id; returns the id.
  Future<String> saveExpense(Expense expense);
  Future<void> deleteExpense(String id);

  Future<List<ExpenseAttachment>> getAttachments(String expenseId);

  /// [dataBase64]: the file content, base64-encoded.
  Future<ExpenseAttachment> addAttachment(
      String expenseId, String fileName, String mimeType, String dataBase64);

  /// Base64 file content, or null if gone.
  Future<String?> getAttachmentData(String id);
  Future<void> deleteAttachment(String id);

  Future<List<RecurringExpense>> getRecurring();
  Future<void> saveRecurring(RecurringExpense recurring);
  Future<void> deleteRecurring(String id);
  Future<List<RecurringExpense>> getDueRecurring(DateTime asOf);

  /// Saves the confirmed occurrence and advances the template's due date.
  Future<void> recordRecurring(String recurringId, Expense expense);
}
