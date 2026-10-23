// app_config.dart
class AppConfig
{
  static const kIsCloud = false;
  /// Data lives on the invoiso server (Railway / docker compose), not in a
  /// local SQLite file. Build with --dart-define=LOCAL_MODE=true for the
  /// original offline behaviour.
  // Not const so tests of the local mode can switch it off.
  static bool useServer = !bool.fromEnvironment('LOCAL_MODE');
  static const name = "invoiso";
  static const version = "v4.4.8";
  static const developer = "ANOOP P";
  static const supportEmail = "anooppkrishnan96@gmail.com";
  static const supportForm = "https://forms.gle/k2Pk7CHr4fAewE7VA";
  static const buyMeCoffee = "https://buymeacoffee.com/anoopp";
  static const website = "https://invoiso.co.in/";
  static const license = "MIT";
  static const description = "Invoiso is a modern invoice and quotation management app for freelancers and small businesses.";
}
