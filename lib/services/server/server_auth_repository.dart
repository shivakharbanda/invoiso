import 'package:invoiso/database/company_registry_service.dart';
import 'package:invoiso/utils/session_manager.dart';
import 'package:invoiso_core/models/user.dart';
import 'package:invoiso_core/rpc/http_repositories.g.dart';
import 'package:invoiso_core/rpc/rpc_client.dart';

import 'app_server.dart';
import 'server_connection.dart';

/// Server-mode auth: credential checks go through the server's rate-limited
/// /auth/login (which also starts the session) instead of an RPC call, and
/// logging out also drops the session token on this device.
class ServerAuthRepository extends HttpAuthRepository {
  ServerAuthRepository() : super(AppServer.rpc);

  /// Logs into the company picked on the login screen. Null for wrong
  /// credentials; other failures (server unreachable, too many attempts)
  /// throw [RpcException] for the caller to show.
  @override
  Future<User?> getUser(String username, String password) async {
    final companyId = await CompanyRegistryService.getActiveCompanyId();
    if (companyId == null) {
      throw RpcException('no_company', 'The server has no companies yet');
    }
    try {
      final session = await AppServer.login(
          ServerCompany(companyId, ''), username, password);
      return User.fromMap(session.user);
    } on RpcException catch (e) {
      if (e.code == 'invalid_credentials') return null;
      rethrow;
    }
  }

  @override
  Future<void> logoutAndSessionReset() async {
    SessionManager.dispose();
    AppServer.logout();
  }
}
