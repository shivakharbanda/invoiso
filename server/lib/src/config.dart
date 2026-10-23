import 'dart:io';

/// Server settings, all from environment variables (Railway / docker-compose).
class ServerConfig {
  ServerConfig({
    required this.databaseUrl,
    required this.tokenSecret,
    this.port = 8080,
    this.tokenTtl = const Duration(hours: 12),
    this.initialAdminPassword,
  });

  /// `postgresql://user:pass@host:port/db?sslmode=disable`
  final String databaseUrl;

  /// HMAC key for login tokens. Changing it logs everyone out.
  final String tokenSecret;
  final int port;
  final Duration tokenTtl;

  /// Password for the `admin` user of the first company, created on first
  /// boot. When unset a random one is generated and printed once to the log.
  final String? initialAdminPassword;

  static ServerConfig fromEnvironment([Map<String, String>? env]) {
    final e = env ?? Platform.environment;
    String need(String key) {
      final v = e[key];
      if (v == null || v.trim().isEmpty) {
        throw StateError('Missing required environment variable $key');
      }
      return v.trim();
    }

    final secret = need('TOKEN_SECRET');
    if (secret.length < 32) {
      throw StateError('TOKEN_SECRET must be at least 32 characters');
    }
    final pw = e['INITIAL_ADMIN_PASSWORD']?.trim();
    return ServerConfig(
      databaseUrl: need('DATABASE_URL'),
      tokenSecret: secret,
      port: int.tryParse(e['PORT'] ?? '') ?? 8080,
      tokenTtl: Duration(hours: int.tryParse(e['TOKEN_TTL_HOURS'] ?? '') ?? 12),
      initialAdminPassword: pw == null || pw.isEmpty ? null : pw,
    );
  }
}
