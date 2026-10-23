import 'package:invoiso_core/database/expense_service.dart';
import 'package:invoiso_core/models/expense.dart';
import 'package:invoiso_core/repositories/expense_repository.dart';

class SqliteExpenseRepository implements ExpenseRepository {
  @override
  Future<List<ExpenseCategory>> getCategories() => ExpenseService.getCategories();

  @override
  Future<void> saveCategory(ExpenseCategory category) =>
      ExpenseService.saveCategory(category);

  @override
  Future<void> deleteCategory(String id) => ExpenseService.deleteCategory(id);

  @override
  Future<List<Project>> getProjects({bool includeArchived = false}) =>
      ExpenseService.getProjects(includeArchived: includeArchived);

  @override
  Future<void> saveProject(Project project) => ExpenseService.saveProject(project);

  @override
  Future<List<Expense>> getExpenses(ExpenseFilter filter,
          {int limit = 200, int offset = 0}) =>
      ExpenseService.getExpenses(filter, limit: limit, offset: offset);

  @override
  Future<int> countExpenses(ExpenseFilter filter) =>
      ExpenseService.countExpenses(filter);

  @override
  Future<Expense?> getExpense(String id) => ExpenseService.getExpense(id);

  @override
  Future<String> saveExpense(Expense expense) => ExpenseService.saveExpense(expense);

  @override
  Future<void> deleteExpense(String id) => ExpenseService.deleteExpense(id);

  @override
  Future<List<ExpenseAttachment>> getAttachments(String expenseId) =>
      ExpenseService.getAttachments(expenseId);

  @override
  Future<ExpenseAttachment> addAttachment(String expenseId, String fileName,
          String mimeType, String dataBase64) =>
      ExpenseService.addAttachment(expenseId, fileName, mimeType, dataBase64);

  @override
  Future<String?> getAttachmentData(String id) =>
      ExpenseService.getAttachmentData(id);

  @override
  Future<void> deleteAttachment(String id) => ExpenseService.deleteAttachment(id);

  @override
  Future<List<RecurringExpense>> getRecurring() => ExpenseService.getRecurring();

  @override
  Future<void> saveRecurring(RecurringExpense recurring) =>
      ExpenseService.saveRecurring(recurring);

  @override
  Future<void> deleteRecurring(String id) => ExpenseService.deleteRecurring(id);

  @override
  Future<List<RecurringExpense>> getDueRecurring(DateTime asOf) =>
      ExpenseService.getDueRecurring(asOf);

  @override
  Future<void> recordRecurring(String recurringId, Expense expense) =>
      ExpenseService.recordRecurring(recurringId, expense);
}
