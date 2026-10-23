import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:invoiso/common/app_config.dart';
import 'package:invoiso/common/setting_key.dart';
import 'package:invoiso/database/company_registry_service.dart';
import 'package:invoiso/database/database_helper.dart';
import 'package:invoiso/l10n/app_localizations.dart';
import 'package:invoiso/providers/locale_provider.dart';
import 'package:invoiso/providers/purchase_bills_settings_provider.dart';
import 'package:invoiso/providers/repositories.dart';
import 'package:invoiso/providers/sqlite_repository_overrides.dart';
import 'package:invoiso/providers/theme_provider.dart';
import 'package:invoiso/theme/app_theme.dart';
import 'package:invoiso/repositories/sqlite/sqlite_company_info_repository.dart';
import 'package:invoiso/repositories/sqlite/sqlite_installation_repository.dart';
import 'package:invoiso/repositories/sqlite/sqlite_invoice_repository.dart';
import 'package:invoiso/repositories/sqlite/sqlite_payment_repository.dart';
import 'package:invoiso/repositories/sqlite/sqlite_settings_repository.dart';
import 'package:invoiso/screens/splash_screen.dart';
import 'package:invoiso/services/backend_services.dart';
import 'package:invoiso/database/user_service.dart';
import 'package:invoiso/providers/http_repository_overrides.dart';
import 'package:invoiso/screens/auth/login_screen.dart';
import 'package:invoiso/services/server/app_server.dart';
import 'package:invoiso_core/rpc/http_repositories.g.dart';
import 'package:invoiso/utils/session_manager.dart';
import 'package:invoiso/utils/window_title.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' show databaseFactorySqflitePlugin;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  // Set up error handlers BEFORE runApp
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    if (kDebugMode) {
      debugPrint('[PlatformDispatcher] Unhandled error: $error');
      debugPrint('Stack: $stack');
    }
    return true;
  };

  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              'Something went wrong',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              kDebugMode ? details.exceptionAsString() : 'Please restart the app.',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  };

  if (!Platform.isAndroid) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  } else {
    databaseFactory = databaseFactorySqflitePlugin;
  }
  DatabaseHelper.dataDirectoryProvider =
      () async => (await getApplicationSupportDirectory()).path;
  UserService.onLogout = SessionManager.dispose;
  WidgetsFlutterBinding.ensureInitialized();
  registerFallbackNumberSymbols();
  if (AppConfig.useServer) {
    await AppServer.init();
    BackendServices.configure(
      settings: HttpSettingsRepository(AppServer.rpc),
      companyInfo: HttpCompanyInfoRepository(AppServer.rpc),
      invoices: HttpInvoiceRepository(AppServer.rpc),
      payments: HttpPaymentRepository(AppServer.rpc),
      installation: SqliteInstallationRepository(),
    );
  } else {
    await CompanyRegistryService.ensureDefaultCompanyRegistered();
    DatabaseHelper().setActiveFileNameBeforeFirstOpen(
        await CompanyRegistryService.getActiveCompanyDbFileName());
    await CompanyRegistryService.nameActiveDbIfMissing();
    BackendServices.configure(
      settings: SqliteSettingsRepository(),
      companyInfo: SqliteCompanyInfoRepository(),
      invoices: SqliteInvoiceRepository(),
      payments: SqlitePaymentRepository(),
      installation: SqliteInstallationRepository()
    );
  }

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();

    const WindowOptions options = WindowOptions(
      minimumSize: Size(600, 400),
      center: true,
      backgroundColor: Colors.white,
      titleBarStyle: TitleBarStyle.normal,
    );

    windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.center();
      await windowManager.show();
      await windowManager.focus();
    });

    // Server mode: the title lists server companies — never block startup
    // on the network (the splash screen reports an unreachable server).
    try {
      await refreshWindowTitle();
    } catch (_) {}
  }

  runApp(ProviderScope(
    overrides: AppConfig.useServer
        ? httpRepositoryOverrides
        : sqliteRepositoryOverrides,
    child: const MyApp()
  ));
}

/// Lets non-widget code (e.g. an expired server session) navigate.
final appNavigatorKey = GlobalKey<NavigatorState>();

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  @override
  void initState() {
    super.initState();
    if (AppConfig.useServer) {
      // Per-company preferences come from the server after login
      // (loadCompanyPreferences); before that the defaults apply.
      AppServer.onSessionExpired = _returnToLoginAfterExpiry;
      return;
    }
    _loadThemeMode();
    _loadAppLocale();
    _loadPurchaseBillsAndSuppliersEnabled();
  }

  void _returnToLoginAfterExpiry() {
    SessionManager.dispose();
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;
    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
    final ctx = appNavigatorKey.currentContext;
    if (ctx != null) {
      ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(ctx)!.dashboardSessionExpiredMessage)));
    }
  }

  Future<void> _loadThemeMode() async {
    final key = await ref.read(settingsRepositoryProvider).getThemeMode();
    if (!mounted) return;
    ref.read(themeModeProvider.notifier).state = themeModeFromKey(key);
  }

  Future<void> _loadAppLocale() async {
    final key = await ref.read(settingsRepositoryProvider).getAppLocale();
    if (!mounted) return;
    applyAppLocale(ref, localeFromKey(key));
  }

  Future<void> _loadPurchaseBillsAndSuppliersEnabled() async {
    final value = await ref
        .read(settingsRepositoryProvider)
        .getSetting(SettingKey.enablePurchaseBillsAndSuppliers);
    if (!mounted) return;
    ref.read(enablePurchaseBillsAndSuppliersProvider.notifier).state =
        value == 'true';
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: AppConfig.name,
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        FallbackLocalizationsDelegate<MaterialLocalizations>(GlobalMaterialLocalizations.delegate),
        FallbackLocalizationsDelegate<WidgetsLocalizations>(GlobalWidgetsLocalizations.delegate),
        FallbackLocalizationsDelegate<CupertinoLocalizations>(GlobalCupertinoLocalizations.delegate),
      ],
      home: const SplashScreen(),
    );
  }
}
