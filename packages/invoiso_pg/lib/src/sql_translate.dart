/// Rewrites the SQLite dialect used by invoiso_core's services into Postgres.
///
/// The services were written for SQLite; rather than fork them, every
/// statement passes through here. The rewrites are deliberately narrow — only
/// the constructs the codebase actually uses (audited in the Phase 1 plan):
///
/// * `?` placeholders            → `$1, $2, …`
/// * `LIKE`                      → `ILIKE` (SQLite LIKE is case-insensitive)
/// * `<ident> COLLATE NOCASE`    → `LOWER(<ident>)`
/// * `strftime('%Y-%m', <expr>)` → `substr(<expr>, 1, 7)` (dates are ISO text)
/// * `TRIM(x, chars)` → `btrim(x, chars)`; `char(n)` → `chr(n)`
/// * `x GLOB '<literal>'` → `x SIMILAR TO '<pattern>'`
/// * `CAST(<expr> AS INTEGER)`   → `safe_int(<expr>)` — SQLite's CAST takes the
///   leading integer and yields 0 for junk; Postgres would throw. `safe_int`
///   is created by `SchemaSync`.
///
/// Everything inside single-quoted literals and double-quoted identifiers is
/// left untouched.
String translateSql(String sql) {
  var out = _rewriteOutsideQuotes(sql, (chunk) {
    chunk = chunk.replaceAllMapped(
        RegExp(r'([A-Za-z_][A-Za-z0-9_.]*)\s+COLLATE\s+NOCASE', caseSensitive: false),
        (m) => 'LOWER(${m[1]})');
    chunk = chunk.replaceAllMapped(
        RegExp(r'(^|[^A-Za-z_])LIKE\b', caseSensitive: false),
        (m) => '${m[1]}ILIKE');
    chunk = chunk.replaceAllMapped(
        RegExp(r'\bchar\((\d+)\)', caseSensitive: false), (m) => 'chr(${m[1]})');
    return chunk;
  });
  out = _rewriteGlob(out);
  out = _rewriteFunctionCalls(out, 'TRIM', (args) {
    final parts = _splitTopLevelArgs(args);
    return parts.length == 2
        ? 'btrim(${parts[0].trim()}, ${parts[1].trim()})'
        : 'TRIM($args)';
  });
  out = _rewriteFunctionCalls(out, 'strftime', (args) {
    final parts = _splitTopLevelArgs(args);
    if (parts.length == 2 && parts[0].trim() == "'%Y-%m'") {
      return 'substr(${parts[1].trim()}, 1, 7)';
    }
    throw UnsupportedError('strftime format not supported on Postgres: $args');
  });
  out = _rewriteFunctionCalls(out, 'CAST', (args) {
    final m = RegExp(r'^(.*)\s+AS\s+INTEGER\s*$', caseSensitive: false, dotAll: true)
        .firstMatch(args);
    if (m == null) return 'CAST($args)';
    return 'safe_int(${m[1]!.trim()})';
  });
  return _numberPlaceholders(out);
}

/// `x GLOB '<literal>'` → `x SIMILAR TO '<pattern>'`: both case-sensitive,
/// `[...]` classes carry over, `*` → `%`, `?` → `_`.
String _rewriteGlob(String sql) {
  return sql.replaceAllMapped(
      RegExp(r"\bGLOB\s+'([^']*)'", caseSensitive: false), (m) {
    final pattern = m[1]!.replaceAll('*', '%').replaceAll('?', '_');
    return "SIMILAR TO '$pattern'";
  });
}

/// Applies [fn] to every stretch of [sql] that is outside quotes.
String _rewriteOutsideQuotes(String sql, String Function(String chunk) fn) {
  final buf = StringBuffer();
  final chunk = StringBuffer();
  var i = 0;
  while (i < sql.length) {
    final c = sql[i];
    if (c == "'" || c == '"') {
      buf.write(fn(chunk.toString()));
      chunk.clear();
      final end = _quoteEnd(sql, i);
      buf.write(sql.substring(i, end));
      i = end;
      continue;
    }
    chunk.write(c);
    i++;
  }
  buf.write(fn(chunk.toString()));
  return buf.toString();
}

/// Index just past the closing quote of the literal starting at [start];
/// doubled quotes (`''`) are escapes.
int _quoteEnd(String sql, int start) {
  final q = sql[start];
  var i = start + 1;
  while (i < sql.length) {
    if (sql[i] == q) {
      if (i + 1 < sql.length && sql[i + 1] == q) {
        i += 2;
        continue;
      }
      return i + 1;
    }
    i++;
  }
  return sql.length;
}

/// Replaces each `name( … )` call (case-insensitive, outside quotes, balanced
/// parentheses) with `fn(innerArgs)`. Nested calls are rewritten first.
String _rewriteFunctionCalls(
    String sql, String name, String Function(String args) fn) {
  final call = RegExp('$name\\s*\\(', caseSensitive: false);
  final identChar = RegExp(r'[A-Za-z0-9_]');
  final buf = StringBuffer();
  var i = 0;
  while (i < sql.length) {
    final c = sql[i];
    if (c == "'" || c == '"') {
      final end = _quoteEnd(sql, i);
      buf.write(sql.substring(i, end));
      i = end;
      continue;
    }
    final atWordStart = i == 0 || !identChar.hasMatch(sql[i - 1]);
    final m = atWordStart ? call.matchAsPrefix(sql, i) : null;
    if (m != null) {
      final open = m.end - 1;
      final close = _matchingParen(sql, open);
      if (close > open) {
        final inner =
            _rewriteFunctionCalls(sql.substring(open + 1, close), name, fn);
        buf.write(fn(inner));
        i = close + 1;
        continue;
      }
    }
    buf.write(c);
    i++;
  }
  return buf.toString();
}

int _matchingParen(String sql, int open) {
  var depth = 0;
  var i = open;
  while (i < sql.length) {
    final c = sql[i];
    if (c == "'" || c == '"') {
      i = _quoteEnd(sql, i);
      continue;
    }
    if (c == '(') depth++;
    if (c == ')') {
      depth--;
      if (depth == 0) return i;
    }
    i++;
  }
  return -1;
}

List<String> _splitTopLevelArgs(String args) {
  final parts = <String>[];
  var depth = 0;
  var start = 0;
  var i = 0;
  while (i < args.length) {
    final c = args[i];
    if (c == "'" || c == '"') {
      i = _quoteEnd(args, i);
      continue;
    }
    if (c == '(') depth++;
    if (c == ')') depth--;
    if (c == ',' && depth == 0) {
      parts.add(args.substring(start, i));
      start = i + 1;
    }
    i++;
  }
  parts.add(args.substring(start));
  return parts;
}

String _numberPlaceholders(String sql) {
  final buf = StringBuffer();
  var n = 0;
  var i = 0;
  while (i < sql.length) {
    final c = sql[i];
    if (c == "'" || c == '"') {
      final end = _quoteEnd(sql, i);
      buf.write(sql.substring(i, end));
      i = end;
      continue;
    }
    if (c == '?') {
      n++;
      buf.write('\$$n');
    } else {
      buf.write(c);
    }
    i++;
  }
  return buf.toString();
}
