import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Who is calling: decoded from a valid login token.
class Session {
  Session({
    required this.companyId,
    required this.userId,
    required this.isAdmin,
    required this.expiresAt,
  });

  final String companyId;
  final String userId;
  final bool isAdmin;
  final DateTime expiresAt;
}

/// Stateless signed tokens: `base64url(json payload).base64url(hmac)`.
class TokenSigner {
  TokenSigner(String secret) : _hmac = Hmac(sha256, utf8.encode(secret));

  final Hmac _hmac;

  String issue(Session s) {
    final payload = base64Url.encode(utf8.encode(jsonEncode({
      'cid': s.companyId,
      'uid': s.userId,
      'adm': s.isAdmin,
      'exp': s.expiresAt.millisecondsSinceEpoch ~/ 1000,
    }))).replaceAll('=', '');
    return '$payload.${_sign(payload)}';
  }

  /// Null when the token is malformed, tampered with or expired.
  Session? verify(String token, {DateTime? now}) {
    final dot = token.indexOf('.');
    if (dot <= 0) return null;
    final payload = token.substring(0, dot);
    final sig = token.substring(dot + 1);
    if (!_constantTimeEquals(sig, _sign(payload))) return null;
    try {
      final map = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(payload))))
          as Map<String, dynamic>;
      final exp = DateTime.fromMillisecondsSinceEpoch((map['exp'] as int) * 1000);
      if ((now ?? DateTime.now()).isAfter(exp)) return null;
      return Session(
        companyId: map['cid'] as String,
        userId: map['uid'] as String,
        isAdmin: map['adm'] as bool,
        expiresAt: exp,
      );
    } catch (_) {
      return null;
    }
  }

  String _sign(String payload) =>
      base64Url.encode(_hmac.convert(utf8.encode(payload)).bytes).replaceAll('=', '');

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

/// Failed-login throttle: at most [maxAttempts] failures per key (client IP +
/// company + username) within [window]. In-memory, so it resets on restart.
class LoginThrottle {
  LoginThrottle({this.maxAttempts = 8, this.window = const Duration(minutes: 15)});

  final int maxAttempts;
  final Duration window;
  final _failures = <String, List<DateTime>>{};

  bool isBlocked(String key, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final list = _failures[key]?..removeWhere((d) => t.difference(d) > window);
    return (list?.length ?? 0) >= maxAttempts;
  }

  void recordFailure(String key, {DateTime? now}) =>
      _failures.putIfAbsent(key, () => []).add(now ?? DateTime.now());

  void reset(String key) => _failures.remove(key);
}
