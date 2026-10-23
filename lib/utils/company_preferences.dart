import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:invoiso/common/setting_key.dart';
import 'package:invoiso/providers/locale_provider.dart';
import 'package:invoiso/providers/purchase_bills_settings_provider.dart';
import 'package:invoiso/providers/repositories.dart';
import 'package:invoiso/providers/theme_provider.dart';

/// Applies the per-company preferences held in that company's settings:
/// theme, language and the Purchase Bills toggle. In server mode these can
/// only be read once logged in, so login calls this.
Future<void> loadCompanyPreferences(WidgetRef ref) async {
  final settings = ref.read(settingsRepositoryProvider);
  final themeKey = await settings.getThemeMode();
  final localeKey = await settings.getAppLocale();
  final purchaseBills =
      await settings.getSetting(SettingKey.enablePurchaseBillsAndSuppliers);
  ref.read(themeModeProvider.notifier).state = themeModeFromKey(themeKey);
  applyAppLocale(ref, localeFromKey(localeKey));
  ref.read(enablePurchaseBillsAndSuppliersProvider.notifier).state =
      purchaseBills == 'true';
}
