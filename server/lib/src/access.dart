import 'auth.dart';

/// Server-side access rules for RPC methods. The desktop UI already hides
/// these from non-admins; the server must not trust that.
class AccessPolicy {
  /// Never callable over RPC: credential checks go through /auth/login
  /// (rate-limited) instead.
  static const blocked = {'auth.getUser'};

  /// Admin only, regardless of arguments.
  static const adminOnly = {
    'auth.insertUser',
    'auth.deleteUserSafely',
    'auth.getAllUsers',
    'auth.userExists',
    'customer.deleteAllCustomers',
    'invoice.permanentDeleteInvoice',
  };

  /// Admin, or a user acting on their own account (`id` argument).
  static const selfOrAdmin = {
    'auth.updateUser',
    'auth.updatePassword',
    'auth.markPasswordChanged',
  };

  /// Null when allowed, otherwise the reason.
  static String? check(String method, Session s, Map<String, dynamic> args) {
    if (blocked.contains(method)) return 'not available over the API';
    if (adminOnly.contains(method) && !s.isAdmin) return 'admin only';
    if (selfOrAdmin.contains(method) && !s.isAdmin) {
      final target = args['id'] ?? (args['user'] as Map?)?['id'];
      if (target != s.userId) return 'admin only';
    }
    return null;
  }

  /// Password hashes and salts never leave the server (blanked rather than
  /// removed so `User.fromMap` still decodes).
  static Object? redact(String method, Object? result) {
    if (!method.startsWith('auth.')) return result;
    Object? strip(Object? v) {
      if (v is List) return v.map(strip).toList();
      if (v is Map && v.containsKey('password')) {
        return {...v, 'password': '', 'salt': null};
      }
      return v;
    }

    return strip(result);
  }
}
