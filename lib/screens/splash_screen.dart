import 'package:flutter/material.dart';
import 'package:invoiso/common/app_config.dart';
import 'package:invoiso/database/database_helper.dart';
import 'package:invoiso/services/server/app_server.dart';
import 'package:invoiso/widgets/server_settings_dialog.dart';
import 'package:invoiso_core/rpc/rpc_client.dart';
import 'package:invoiso/l10n/app_localizations.dart';
import 'package:invoiso/screens/auth/login_screen.dart';
import 'package:invoiso/common/constants.dart';
import 'package:invoiso/utils/app_logger.dart';

const _tag = 'SplashScreen';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    if (AppConfig.useServer) return _checkServer();
    try {
      await DatabaseHelper().database;
    } catch (e, stack) {
      AppLogger.e(_tag, 'Database initialization failed', e, stack);
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.splashInitErrorTitle),
          content: Text(l10n.splashInitErrorMessage('$e')),
          actions: [
            ElevatedButton(
              onPressed: () => _initializeApp(),
              child: Text(l10n.actionRetry),
            ),
          ],
        ),
      );
      return;
    }

    AppLogger.d(_tag, 'DB path: ${DatabaseHelper.path}');

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  /// Server mode: nothing to open locally — just make sure the configured
  /// server answers before showing the login screen.
  Future<void> _checkServer() async {
    try {
      await AppServer.connection.health();
    } on RpcException catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      final action = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.splashInitErrorTitle),
          content: Text(
              '${l10n.serverSettingsFailed(e.message)}\n\n'
              '${AppServer.connection.baseUrl}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'settings'),
              child: Text(l10n.serverSettingsTitle),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, 'retry'),
              child: Text(l10n.actionRetry),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (action == 'settings') {
        final url = await showServerSettingsDialog(context);
        if (url != null) AppServer.useBaseUrl(url);
      }
      return _checkServer();
    }
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(AppLocalizations.of(context)!.splashInitializingMessage,
                style: const TextStyle(fontSize: 18)),
            AppSpacing.hXlarge,
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
