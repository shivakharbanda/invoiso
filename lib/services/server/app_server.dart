import 'package:invoiso_core/rpc/rpc_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'server_connection.dart';

/// The app's single link to the invoiso server (server mode only — see
/// `AppConfig.useServer`). Repositories are created once at startup and talk
/// to [rpc], which always forwards to the *current* [connection], so the
/// server address can change at the login screen without rebuilding them.
class AppServer {
  static ServerConnection? _connection;

  /// The company the user is logged into (null before login).
  static ServerCompany? company;

  static ServerConnection get connection =>
      _connection ?? (throw StateError('AppServer.init() was never called'));

  /// Called when the server rejects the session; set by the app shell to
  /// return to the login screen.
  static void Function()? onSessionExpired;

  static final RpcClient rpc = _AppRpc();

  static Future<void> init() async => useBaseUrl(await ServerSettings.load());

  static void useBaseUrl(String baseUrl) {
    _connection = ServerConnection(baseUrl)
      ..onUnauthorized = () {
        _AppRpc.clearCache();
        onSessionExpired?.call();
      };
    company = null;
    _AppRpc.clearCache();
  }

  static Future<ServerSession> login(
      ServerCompany company, String username, String password) async {
    _AppRpc.clearCache();
    final session = await connection.login(company.id, username, password);
    AppServer.company = session.company;
    return session;
  }

  static void logout() {
    _connection?.logout();
    company = null;
    _AppRpc.clearCache();
  }
}

/// RPC client used by every `Http*Repository`:
/// * forwards to the current [AppServer.connection];
/// * caches settings and company-info reads (screens read dozens of settings
///   each; they change rarely and only through these same repositories, so
///   any write to the repository drops its cache);
/// * keeps device-level caches (FAQ, update check) in local preferences
///   instead of the shared company settings on the server.
class _AppRpc implements RpcClient {
  static final _cache = <String, Object?>{};
  static const _cachedRepos = {'settings', 'companyInfo'};
  static const _deviceLocalKeys = {
    'faqCache',
    'lastFaqFetch',
    'lastUpdateCheck',
    'lastKnownLatestVersion',
    'lastNotifiedVersion',
  };

  static void clearCache() => _cache.clear();

  @override
  Future<Object?> call(String method, Map<String, Object?> args) async {
    final dot = method.indexOf('.');
    final repo = method.substring(0, dot);
    final name = method.substring(dot + 1);

    final key = args['key'];
    if (repo == 'settings' && key is String && _deviceLocalKeys.contains(key)) {
      return _deviceLocal(name, key, args['value']);
    }

    if (!_cachedRepos.contains(repo)) {
      return AppServer.connection.call(method, args);
    }
    if (!name.startsWith('get')) {
      _cache.removeWhere((k, _) => k.startsWith('$repo.'));
      return AppServer.connection.call(method, args);
    }
    final cacheKey = '$method ${args.toString()}';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey];
    final result = await AppServer.connection.call(method, args);
    _cache[cacheKey] = result;
    return result;
  }

  static Future<Object?> _deviceLocal(String name, String key, Object? value) async {
    final prefs = await SharedPreferences.getInstance();
    final prefKey = 'device_setting_$key';
    switch (name) {
      case 'getSetting':
        return prefs.getString(prefKey);
      case 'setSetting':
        await prefs.setString(prefKey, value as String);
        return null;
      case 'deleteSetting':
        await prefs.remove(prefKey);
        return null;
    }
    return AppServer.connection.call('settings.$name', {'key': key});
  }
}
