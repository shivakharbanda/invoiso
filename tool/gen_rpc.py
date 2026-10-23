"""Generates the RPC layer from invoiso_core's repository interfaces.

Outputs (both in packages/invoiso_core/lib/rpc/):
  rpc_handlers.g.dart      server: 'repo.method' -> decode args, call, encode
  http_repositories.g.dart client: Http<X>Repository implements <X>Repository

Every interface method is `Future<T> name(params)`. Types are mapped to JSON
by kind, discovered by scanning models/ and common/:
  int/double/num/String/bool  as-is
  DateTime                    ISO-8601 string
  enums                       .name / values.byName
  classes with fromJson       toJson()/fromJson
  classes with fromMap        toMap()/fromMap
  records and record typedefs {field: value}
  List<T>, Map<String, T>     element-wise

Run from the repo root:  python tool/gen_rpc.py
Re-run after changing any repository interface.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CORE = os.path.join(ROOT, 'packages', 'invoiso_core', 'lib')
OUT = os.path.join(CORE, 'rpc')

# Interfaces that never cross the wire (client-local or server-only).
SKIP_REPOS = {'InstallationRepository'}

PRIMS = {'int', 'double', 'num', 'String', 'bool', 'dynamic', 'Object'}


def read(path):
    with open(path, encoding='utf-8') as f:
        return f.read()


def scan_types():
    kinds, records = {}, {}
    for sub in ('models', 'common'):
        d = os.path.join(CORE, sub)
        for name in os.listdir(d):
            if not name.endswith('.dart'):
                continue
            src = read(os.path.join(d, name))
            for m in re.finditer(r'^enum (\w+)', src, re.M):
                kinds[m.group(1)] = 'enum'
            for m in re.finditer(r'^class (\w+)', src, re.M):
                cls = m.group(1)
                if re.search(r'factory %s\.fromJson\(' % cls, src):
                    kinds[cls] = 'json'
                elif re.search(r'factory %s\.fromMap\(' % cls, src):
                    kinds[cls] = 'map'
            for m in re.finditer(r'^typedef (\w+) = \((\{.*?\})\);', src, re.M | re.S):
                records[m.group(1)] = m.group(2)
    return kinds, records


def split_top(s, sep=','):
    parts, depth, cur = [], 0, ''
    for ch in s:
        if ch in '<({[':
            depth += 1
        elif ch in '>)}]':
            depth -= 1
        if ch == sep and depth == 0:
            parts.append(cur)
            cur = ''
        else:
            cur += ch
    if cur.strip():
        parts.append(cur)
    return [p.strip() for p in parts if p.strip()]


def record_fields(body):
    """'{int a, String? b}' -> [('int','a'), ('String?','b')]"""
    inner = re.sub(r'//.*', '', body.strip()[1:-1])
    out = []
    for f in split_top(inner):
        t, n = f.rsplit(' ', 1)
        out.append((t.strip(), n.strip()))
    return out


class Codec:
    def __init__(self, kinds, records):
        self.kinds, self.records = kinds, records

    def enc(self, t, e, d=0):
        t = t.strip()
        if t.endswith('?'):
            simple = re.fullmatch(r'\w+', e) is not None  # locals promote
            ref = e if simple else f'{e}!'
            inner = self.enc(t[:-1], ref, d)
            if inner == ref:
                return e
            if simple and re.fullmatch(re.escape(e) + r'\.\w+(\(\))?', inner):
                return e + '?' + inner[len(e):]
            return f'({e} == null ? null : {inner})'
        if t in PRIMS:
            return e
        if t == 'DateTime':
            return f'{e}.toIso8601String()'
        m = re.fullmatch(r'List<(.+)>', t)
        if m:
            x = f'x{d}'
            body = self.enc(m.group(1), x, d + 1)
            return e if body == x else f'{e}.map(({x}) => {body}).toList()'
        m = re.fullmatch(r'Map<String,\s*(.+)>', t)
        if m:
            k, v = f'k{d}', f'v{d}'
            body = self.enc(m.group(1), v, d + 1)
            return e if body == v else f'{e}.map(({k}, {v}) => MapEntry({k}, {body}))'
        if t.startswith('({') or t in self.records:
            fields = record_fields(t[1:-1] if t.startswith('(') else self.records[t])
            items = ', '.join(f"'{n}': {self.enc(ft, f'{e}.{n}', d + 1)}" for ft, n in fields)
            return f'<String, dynamic>{{{items}}}'
        kind = self.kinds.get(t)
        if kind == 'enum':
            return f'{e}.name'
        if kind == 'json':
            return f'{e}.toJson()'
        if kind == 'map':
            return f'{e}.toMap()'
        raise ValueError(f'no codec for {t}')

    def dec(self, t, e, d=0):
        t = t.strip()
        if t.endswith('?'):
            base = t[:-1]
            if base == 'int':
                return f'({e} as num?)?.toInt()'
            if base == 'double':
                return f'({e} as num?)?.toDouble()'
            if base in ('String', 'bool', 'num'):
                return f'{e} as {base}?'
            return f'({e} == null ? null : {self.dec(base, e, d)})'
        if t == 'int':
            return f'({e} as num).toInt()'
        if t == 'double':
            return f'({e} as num).toDouble()'
        if t == 'num':
            return f'{e} as num'
        if t in ('String', 'bool'):
            return f'{e} as {t}'
        if t in ('dynamic', 'Object'):
            return e
        if t == 'DateTime':
            return f'DateTime.parse({e} as String)'
        m = re.fullmatch(r'List<(.+)>', t)
        if m:
            x = f'x{d}'
            return f'[for (final {x} in {e} as List) {self.dec(m.group(1), x, d + 1)}]'
        m = re.fullmatch(r'Map<String,\s*(.+)>', t)
        if m:
            k, v = f'k{d}', f'v{d}'
            return (f'({e} as Map).map(({k}, {v}) => '
                    f'MapEntry({k} as String, {self.dec(m.group(1), v, d + 1)}))')
        if t.startswith('({') or t in self.records:
            fields = record_fields(t[1:-1] if t.startswith('(') else self.records[t])
            r = f'r{d}'
            items = ', '.join(f"{n}: {self.dec(ft, f'{r}[{chr(39)}{n}{chr(39)}]', d + 1)}"
                              for ft, n in fields)
            return f'(({r}) => ({items}))(({e} as Map).cast<String, dynamic>())'
        kind = self.kinds.get(t)
        cast = f'({e} as Map).cast<String, dynamic>()'
        if kind == 'enum':
            return f'{t}.values.byName({e} as String)'
        if kind == 'json':
            return f'{t}.fromJson({cast})'
        if kind == 'map':
            return f'{t}.fromMap({cast})'
        raise ValueError(f'no codec for {t}')


class Param:
    def __init__(self, raw, kind):
        self.raw = raw  # exactly as written, reused in client signatures
        self.kind = kind  # 'pos' | 'opt' | 'named'
        p = re.sub(r'^required\s+', '', raw)
        p = re.sub(r'\s*=.*$', '', p, flags=re.S)
        self.type, self.name = [s.strip() for s in p.rsplit(' ', 1)]


def parse_params(s):
    """Positional params, then an optional top-level `[...]` or `{...}` group.
    Braces inside `<>`/`()` (e.g. record types) are not group openers."""
    depth = 0
    for i, ch in enumerate(s):
        if ch in '<(':
            depth += 1
        elif ch in '>)':
            depth -= 1
        elif ch in '{[' and depth == 0:
            kind = 'named' if ch == '{' else 'opt'
            group = s[i + 1:s.rindex('}' if ch == '{' else ']')]
            return ([Param(p, 'pos') for p in split_top(s[:i])] +
                    [Param(p, kind) for p in split_top(group)])
    return [Param(p, 'pos') for p in split_top(s)]


def parse_repos():
    repos = []
    d = os.path.join(CORE, 'repositories')
    for name in sorted(os.listdir(d)):
        if not name.endswith('_repository.dart'):
            continue
        src = read(os.path.join(d, name))
        m = re.search(r'abstract class (\w+)\s*\{(.*)\}\s*$', src, re.S)
        if not m or m.group(1) in SKIP_REPOS:
            continue
        body = re.sub(r'//.*', '', m.group(2))
        methods = []
        for mm in re.finditer(r'Future<(.+?)>\s+(\w+)\s*\((.*?)\);', body, re.S):
            ret, mname, params = mm.group(1), mm.group(2), mm.group(3)
            parsed = parse_params(params)
            for p in parsed:
                needs_default = (p.kind in ('named', 'opt') and '=' not in p.raw
                                 and not p.raw.startswith('required')
                                 and not p.type.endswith('?'))
                if needs_default:
                    p.raw += ' = ' + impl_default(name, mname, p)
            methods.append((ret.strip(), mname, parsed))
        repos.append((m.group(1), name, methods))
    return repos


def impl_default(interface_file, method, param):
    """Interfaces may omit defaults on optional params; the generated client
    copies them from the SQLite implementation so behaviour is identical."""
    src = read(os.path.join(CORE, 'repositories', 'sqlite', 'sqlite_' + interface_file))
    start = re.search(r'\b%s\s*\(' % method, src)
    if start:
        sig = src[start.end():src.find('=>' if '=>' in src[start.end():] else '{', start.end())]
        m = re.search(r'\b%s\s*=\s*([^,}\]]+)' % re.escape(param.name), sig)
        if m:
            return m.group(1).strip()
    raise ValueError(f'no default for {method}.{param.name} in the SQLite implementation')


def repo_key(cls):
    base = cls[:-len('Repository')]
    return base[0].lower() + base[1:]


def imports():
    lines = []
    for sub in ('models', 'common', 'repositories'):
        for name in sorted(os.listdir(os.path.join(CORE, sub))):
            if name.endswith('.dart'):
                lines.append(f"import 'package:invoiso_core/{sub}/{name}';")
    return '\n'.join(lines)


def main():
    kinds, records = scan_types()
    codec = Codec(kinds, records)
    repos = parse_repos()
    os.makedirs(OUT, exist_ok=True)
    header = ('// GENERATED by tool/gen_rpc.py from the repository interfaces.\n'
              '// Do not edit by hand; re-run the generator instead.\n'
              '// ignore_for_file: unused_import, prefer_const_constructors, '
              'unnecessary_cast, unnecessary_parenthesis, unnecessary_import, '
              'prefer_null_aware_operators\n\n')

    # ── server ──
    s = [header, imports(), "\n\n/// One argument map in, one JSON-ready result out.\n",
         'typedef RpcHandler = Future<Object?> Function(Map<String, dynamic> a);\n\n',
         '/// The repositories the server dispatches to (its Postgres-backed ones).\n',
         'class RpcRepositories {\n  RpcRepositories({\n']
    s += [f'    required this.{repo_key(c)},\n' for c, _, _ in repos]
    s.append('  });\n\n')
    s += [f'  final {c} {repo_key(c)};\n' for c, _, _ in repos]
    s.append('}\n\n/// `<repo>.<method>` → handler for every interface method.\n')
    s.append('Map<String, RpcHandler> rpcHandlers(RpcRepositories r) => {\n')
    for c, _, methods in repos:
        k = repo_key(c)
        for ret, name, params in methods:
            pos = [codec.dec(p.type, f"a['{p.name}']") for p in params if p.kind in ('pos', 'opt')]
            named = [f"{p.name}: {codec.dec(p.type, f'a[{chr(39)}{p.name}{chr(39)}]')}"
                     for p in params if p.kind == 'named']
            call = f'r.{k}.{name}({", ".join(pos + named)})'
            if ret == 'void':
                body = f'async {{\n          await {call};\n          return null;\n        }}'
            else:
                body = (f'async {{\n          final res = await {call};\n'
                        f'          return {codec.enc(ret, "res")};\n        }}')
            s.append(f"      '{k}.{name}': (a) {body},\n")
    s.append('    };\n')
    with open(os.path.join(OUT, 'rpc_handlers.g.dart'), 'w', encoding='utf-8', newline='\n') as f:
        f.write(''.join(s))

    # ── client ──
    c_out = [header, imports(), "\nimport 'rpc_client.dart';\n"]
    for c, _, methods in repos:
        k = repo_key(c)
        c_out.append(f'\nclass Http{c} implements {c} {{\n  Http{c}(this._rpc);\n\n  final RpcClient _rpc;\n')
        for ret, name, params in methods:
            pos = [p.raw for p in params if p.kind == 'pos']
            opt = [p.raw for p in params if p.kind == 'opt']
            named = [p.raw for p in params if p.kind == 'named']
            sig = ', '.join(pos)
            if opt:
                sig += (', ' if sig else '') + '[' + ', '.join(opt) + ']'
            if named:
                sig += (', ' if sig else '') + '{' + ', '.join(named) + '}'
            args = ', '.join(f"'{p.name}': {codec.enc(p.type, p.name)}" for p in params)
            call = f"_rpc.call('{k}.{name}', {{{args}}})"
            c_out.append(f'\n  @override\n  Future<{ret}> {name}({sig}) async {{\n')
            if ret == 'void':
                c_out.append(f'    await {call};\n  }}\n')
            else:
                c_out.append(f'    final res = await {call};\n'
                             f'    return {codec.dec(ret, "res")};\n  }}\n')
        c_out.append('}\n')
    with open(os.path.join(OUT, 'http_repositories.g.dart'), 'w', encoding='utf-8', newline='\n') as f:
        f.write(''.join(c_out))
    total = sum(len(m) for _, _, m in repos)
    print(f'{len(repos)} repositories, {total} methods')


if __name__ == '__main__':
    sys.exit(main())
