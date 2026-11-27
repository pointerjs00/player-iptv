/// O formato «devalue» do Nuxt (`<script id="__NUXT_DATA__">`): uma lista em que cada valor é
/// guardado uma vez e referido pelo índice; os objetos e as listas guardam índices, e alguns
/// valores vêm marcados (`["Reactive", i]`, `["Ref", i]`, `["Set", …]`, `["Map", …]`,
/// `["Date", "…"]`).
library;

const _envolventes = {'Reactive', 'ShallowReactive', 'Ref', 'ShallowRef', 'EmptyRef', 'EmptyShallowRef', 'NuxtError'};

/// O valor de `raiz[i]`, com as referências resolvidas (por omissão, a raiz: o índice 0).
Object? lerDevalue(List<dynamic> raiz, [int i = 0]) => _ler(raiz, i, <int>{});

Object? _ler(List<dynamic> raiz, Object? i, Set<int> aCaminho) {
  if (i is! int || i < 0 || i >= raiz.length) return null;
  if (!aCaminho.add(i)) return null; // um ciclo
  try {
    final v = raiz[i];
    if (v is Map) return {for (final e in v.entries) '${e.key}': _ler(raiz, e.value, aCaminho)};
    if (v is List) {
      if (v.isNotEmpty && v.first is String) {
        final marca = v.first as String;
        if (_envolventes.contains(marca)) return v.length > 1 ? _ler(raiz, v[1], aCaminho) : null;
        if (marca == 'Date') return v.length > 1 ? DateTime.tryParse('${v[1]}')?.toUtc() : null;
        if (marca == 'Set') return [for (final x in v.skip(1)) _ler(raiz, x, aCaminho)];
        if (marca == 'Map') {
          final m = <String, Object?>{};
          for (var k = 1; k + 1 < v.length; k += 2) {
            m['${_ler(raiz, v[k], aCaminho)}'] = _ler(raiz, v[k + 1], aCaminho);
          }
          return m;
        }
      }
      return [for (final x in v) _ler(raiz, x, aCaminho)];
    }
    return v;
  } finally {
    aCaminho.remove(i);
  }
}
