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

/// Separador entre palavras do nome ("RTP-1", "RTP.1", "RTP | 1", "Sport_TV1").
const _sep = r'[\s._\-|:/]*';

/// O número 1 ("1" não seguido de dígito) ou "Um" (não seguido de letra/dígito).
const _um = r'(?:1(?![0-9])|Um(?![A-Z0-9]))';

final perfisCanais = <String, PerfilCanal>{
  'rtp1': PerfilCanal('rtp1', 'RTP 1',
      RegExp('(?<![A-Z0-9])RTP$_sep$_um${r'(?!\W*(A[cç]ores|Madeira|Internacional|[AÁ]frica))'}', caseSensitive: false)),
  'sporttv1': PerfilCanal('sporttv1', 'SportTV 1', RegExp('(?<![A-Z0-9])SPORT${_sep}TV$_sep$_um', caseSensitive: false),
      exclusoes: RegExp('PFC', caseSensitive: false), ptObrigatorio: true),
  'dazn1': PerfilCanal('dazn1', 'DAZN 1', RegExp('(?<![A-Z0-9])DAZN$_sep$_um', caseSensitive: false),
      exclusoes: RegExp(r'PPV|EVENT', caseSensitive: false), ptObrigatorio: true),
};

final _grupoPt = RegExp(r'(?<![A-Z])(PT|PRT|PORTUGAL|PORTUGU[EÊ]S\w*)(?![A-Z])', caseSensitive: false);
final _grupoBr = RegExp(r'(?<![A-Z])(BR|BRA[SZ]IL\w*)(?![A-Z])', caseSensitive: false);

/// O group-title é de Portugal (PT, PRT, Portugal, Português…) e não do Brasil.
bool grupoPortugues(String g) => _grupoPt.hasMatch(g) && !_grupoBr.hasMatch(g);

/// Os perfis de ids ("rtp1", "dazn1"), pela ordem fixa; nenhum válido = RTP 1.
List<PerfilCanal> perfisDe(Iterable<String> ids) {
  final escolhidos = [for (final e in perfisCanais.entries) if (ids.contains(e.key)) e.value];
  return escolhidos.isEmpty ? [perfisCanais['rtp1']!] : escolhidos;
}

/// Os itens cujo nome é o canal do perfil, sem repetidos, portugueses (prefixo PT no nome ou grupo
/// de Portugal) primeiro e depois os nomes mais curtos. Se PT for obrigatório, os restantes caem.
List<T> candidatos<T>(PerfilCanal p, Iterable<T> itens, String Function(T) nome,
    [Object Function(T)? chave, String Function(T)? grupo]) {
  bool pt(T i) => reptPrefixo.hasMatch(nome(i)) || (grupo != null && grupoPortugues(grupo(i)));
  final vistos = <Object>{};
  final unicos = <T>[];
  for (final i in itens) {
    final n = nome(i);
    if (!p.padrao.hasMatch(n)) continue;
    if (p.exclusoes?.hasMatch(n) ?? false) continue;
    if (p.ptObrigatorio && !pt(i)) continue;
    if (vistos.add(chave == null ? n : chave(i))) unicos.add(i);
  }
  int peso(T i) => pt(i) ? 0 : 1;
  unicos.sort((a, b) {
    final d = peso(a) - peso(b);
    return d != 0 ? d : nome(a).length - nome(b).length;
  });
  return unicos;
}
