/// Perfis dos canais que a verificação testa (RTP 1, SportTV 1, DAZN 1).
/// Porta de `tv-management/motor/canais.py`.
library;

class PerfilCanal {
  const PerfilCanal(this.id, this.nome, this.padrao, {this.exclusoes, this.ptObrigatorio = false});
  final String id;
  final String nome;
  final RegExp padrao;
  final RegExp? exclusoes;
  final bool ptObrigatorio;
}

final reptPrefixo = RegExp(r'^\W*(PT|PRT|PORTUGAL)(?![A-Z])', caseSensitive: false);

final perfisCanais = <String, PerfilCanal>{
  'rtp1': PerfilCanal('rtp1', 'RTP 1',
      RegExp(r'(?<![A-Z0-9])RTP\s*1(?![0-9])(?!\W*(A[cç]ores|Madeira|Internacional|[AÁ]frica))',
          caseSensitive: false)),
  'sporttv1': PerfilCanal('sporttv1', 'SportTV 1', RegExp(r'(?<![A-Z0-9])SPORT\s*TV\s*1(?![0-9])', caseSensitive: false),
      exclusoes: RegExp('PFC', caseSensitive: false), ptObrigatorio: true),
  'dazn1': PerfilCanal('dazn1', 'DAZN 1', RegExp(r'(?<![A-Z0-9])DAZN\s*1(?![0-9])', caseSensitive: false),
      exclusoes: RegExp(r'PPV|EVENT', caseSensitive: false), ptObrigatorio: true),
};

/// Os perfis de ids ("rtp1", "dazn1"), pela ordem fixa; nenhum válido = RTP 1.
List<PerfilCanal> perfisDe(Iterable<String> ids) {
  final escolhidos = [for (final e in perfisCanais.entries) if (ids.contains(e.key)) e.value];
  return escolhidos.isEmpty ? [perfisCanais['rtp1']!] : escolhidos;
}

/// Os itens cujo nome é o canal do perfil, sem repetidos, portugueses primeiro e depois os
/// nomes mais curtos. Se a marca PT for obrigatória, os restantes são descartados.
List<T> candidatos<T>(PerfilCanal p, Iterable<T> itens, String Function(T) nome, [Object Function(T)? chave]) {
  final vistos = <Object>{};
  final unicos = <T>[];
  for (final i in itens) {
    final n = nome(i);
    if (!p.padrao.hasMatch(n)) continue;
    if (p.exclusoes?.hasMatch(n) ?? false) continue;
    if (p.ptObrigatorio && !reptPrefixo.hasMatch(n)) continue;
    if (vistos.add(chave == null ? n : chave(i))) unicos.add(i);
  }
  int peso(T i) => reptPrefixo.hasMatch(nome(i)) ? 0 : 1;
  unicos.sort((a, b) {
    final d = peso(a) - peso(b);
    return d != 0 ? d : nome(a).length - nome(b).length;
  });
  return unicos;
}
