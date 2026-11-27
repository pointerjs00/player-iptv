/// Reconhecer os canais portugueses nos nomes das listas IPTV, comparar equipas pelo nome e ler
/// os títulos das grelhas (spec §7 e §8).
library;

import '../modelo/canal.dart' show semAcentos;
import 'catalogo.dart';
import 'modelo.dart';

/// Letras «elevadas» que algumas listas usam (ᴴᴰ, ⁴ᴷ, ᶠᴴᴰ) → as normais.
const _elevadas = {
  'ᴴ': 'h', 'ᴰ': 'd', 'ᶠ': 'f', 'ᵁ': 'u', 'ᴷ': 'k', 'ˢ': 's', 'ᴿ': 'r', 'ᴬ': 'a', 'ᵂ': 'w', 'ᵀ': 't', 'ᴵ': 'i',
  'ᴸ': 'l', 'ᴱ': 'e', 'ᴼ': 'o', 'ᴾ': 'p', 'ᴺ': 'n', 'ᴹ': 'm', 'ᴮ': 'b', 'ᴳ': 'g', 'ᴶ': 'j', 'ⱽ': 'v',
  '⁰': '0', '¹': '1', '²': '2', '³': '3', '⁴': '4', '⁵': '5', '⁶': '6', '⁷': '7', '⁸': '8', '⁹': '9', '⁺': '+',
};

String _simples(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    b.write(_elevadas[c] == null ? c : ' ${_elevadas[c]}');
  }
  return semAcentos(b.toString());
}

// ─── canais ──────────────────────────────────────────────────────────────────

class CanalReconhecido {
  const CanalReconhecido(this.canal, this.qualidade, {required this.portugues, required this.confianca});
  final CanalTv canal;
  final Qualidade qualidade;

  /// Sem outro país à vista (no nome ou no grupo).
  final bool portugues;

  /// 1 = o nome atual; menos para nomes antigos (Eleven → DAZN).
  final double confianca;
}

const _qualidades = {
  '4k': Qualidade.uhd, 'uhd': Qualidade.uhd, '2160p': Qualidade.uhd, '8k': Qualidade.uhd,
  'fhd': Qualidade.fhd, '1080p': Qualidade.fhd, '1080': Qualidade.fhd, '1080i': Qualidade.fhd,
  'hd': Qualidade.hd, '720p': Qualidade.hd, '720': Qualidade.hd,
  'sd': Qualidade.sd, '576p': Qualidade.sd, '480p': Qualidade.sd,
};

/// Palavras que não fazem parte do nome do canal.
const _ruido = {
  'hevc', 'h265', 'h264', 'x265', '50fps', '60fps', 'fps', 'backup', 'vip', 'alt', 'raw', 'hq', 'lq', 'ott', 'live',
};

/// Códigos de país que aparecem nas listas (prefixos e sufixos).
const _paises = {
  'pt', 'por', 'es', 'esp', 'de', 'ger', 'it', 'ita', 'fr', 'fra', 'br', 'bra', 'uk', 'gb', 'us', 'usa', 'en', 'ar',
  'tr', 'pl', 'nl', 'be', 'ro', 'ca', 'mx', 'ch', 'at', 'ie', 'al', 'ex', 'latino', 'lat',
};

/// Palavras de país nos grupos.
const _paisesGrupo = {
  'portugal': 'pt', 'portuguese': 'pt', 'espana': 'es', 'spain': 'es', 'deutschland': 'de', 'germany': 'de',
  'italia': 'it', 'italy': 'it', 'france': 'fr', 'brasil': 'br', 'brazil': 'br', 'mexico': 'mx', 'latino': 'lat',
  'usa': 'us', 'canada': 'ca', 'turkey': 'tr', 'turkiye': 'tr', 'polska': 'pl', 'arabic': 'ar', 'arab': 'ar',
};

final Map<String, (CanalTv, String)> _porAlternativo = {
  for (final c in catalogoCanais)
    for (final a in c.alternativos) a: (c, a),
};

/// O país num prefixo ("|PT| …", "PT: …", "[PT] …", "PT - …") e o resto.
(String?, String) _semPrefixo(String s) {
  final m = RegExp(r'^\s*[\|\[\(]\s*([a-z]{2,6})\s*[\|\]\)]\s*').firstMatch(s) ??
      RegExp(r'^\s*([a-z]{2,3})\s*[:\|]\s*').firstMatch(s) ??
      RegExp(r'^\s*([a-z]{2,3})\s+-\s+').firstMatch(s);
  if (m == null || !_paises.contains(m[1])) return (null, s);
  return (m[1], s.substring(m.end));
}

String? _paisDoGrupo(String grupo) {
  final g = _simples(grupo);
  final (p, _) = _semPrefixo(g);
  if (p != null) return _normalizarPais(p);
  for (final palavra in g.split(RegExp(r'[^a-z]+'))) {
    final x = _paisesGrupo[palavra];
    if (x != null) return x;
  }
  return null;
}

String _normalizarPais(String p) => switch (p) { 'por' => 'pt', 'esp' => 'es', 'ger' => 'de', _ => p };

/// O canal português deste nome de uma lista (null = não é um canal do catálogo).
CanalReconhecido? reconhecerCanal(String nomeNaLista, {String grupo = ''}) {
  var (pais, resto) = _semPrefixo(_simples(nomeNaLista));
  var tokens = resto.split(RegExp(r'[^a-z0-9+]+')).where((t) => t.isNotEmpty).toList();
  Qualidade? qualidade;
  final nome = <String>[];
  for (final (i, t) in tokens.indexed) {
    final q = _qualidades[t];
    if (q != null) {
      if (qualidade == null || q.index > qualidade.index) qualidade = q;
      continue;
    }
    if (_ruido.contains(t)) continue;
    // um país solto no princípio ou no fim ("PT SPORT TV 1", "DAZN 1 ES")
    if ((i == 0 || i == tokens.length - 1) && t.length <= 3 && _paises.contains(t) && tokens.length > 1) {
      pais ??= t;
      continue;
    }
    nome.add(t);
  }
  var chave = nome.join();
  var encontrado = _porAlternativo[chave];
  // a qualidade colada ao nome ("SPORTTV1HD")
  if (encontrado == null) {
    for (final q in _qualidades.keys) {
      if (chave.endsWith(q) && _porAlternativo.containsKey(chave.substring(0, chave.length - q.length))) {
        qualidade ??= _qualidades[q];
        chave = chave.substring(0, chave.length - q.length);
        encontrado = _porAlternativo[chave];
        break;
      }
    }
  }
  if (encontrado == null) return null;
  final (canal, alternativo) = encontrado;
  pais = pais == null ? _paisDoGrupo(grupo) : _normalizarPais(pais);
  return CanalReconhecido(canal, qualidade ?? Qualidade.hd,
      portugues: pais == null || pais == 'pt', confianca: alternativo.startsWith('eleven') ? .6 : 1);
}

// ─── equipas ─────────────────────────────────────────────────────────────────

/// Palavras que não distinguem equipas.
const _genericas = {
  'fc', 'sc', 'cf', 'cd', 'sad', 'ac', 'afc', 'sl', 'ss', 'as', 'ud', 'ca', 'cp', 'sv', 'bk', 'fk', 'sk', 'if', 'vfb',
  'vfl', 'tsg', 'rc', 'rcd', 'ogc', 'clube', 'club', 'futebol', 'football', 'de', 'da', 'do', 'dos', 'das', 'the',
  'and', 'e', 'calcio', 'ssc',
};

/// Palavras com outra forma (antes de comparar).
const _palavras = {
  'man': 'manchester', 'utd': 'united', 'nottm': 'nottingham', 'munchen': 'munich', 'muenchen': 'munich',
  'munique': 'munich', 'wolves': 'wolverhampton', 'spurs': 'tottenham', 'inter': 'internazionale',
  'atletico': 'atletico', 'atl': 'atletico', 'sp': 'sporting', 'vit': 'vitoria',
};

/// Equipas com nomes muito diferentes (já normalizadas) → a forma comum.
const _equipas = {
  'vitoria guimaraes': 'vitoria guimaraes', 'vitoria': 'vitoria guimaraes', 'v guimaraes': 'vitoria guimaraes',
  'guimaraes': 'vitoria guimaraes', 'paris saint germain': 'psg', 'paris sg': 'psg',
};

class _Equipa {
  _Equipa(this.palavras, this.marcas);
  final List<String> palavras;

  /// 'b' (reservas), 'sub' (sub-NN), 'f' (feminino).
  final Set<String> marcas;
}

_Equipa _equipa(String nome) {
  var s = _simples(nome).replaceAll('&', ' ');
  final marcas = <String>{};
  if (RegExp(r'\(w\)|\bfem\b|feminin|\bwomen\b|\bladies\b').hasMatch(s)) marcas.add('f');
  s = s.replaceAll(RegExp(r'\(w\)'), ' ');
  final t = s.split(RegExp(r'[^a-z0-9]+')).where((x) => x.isNotEmpty).toList();
  final palavras = <String>[];
  for (var i = 0; i < t.length; i++) {
    final x = t[i];
    if (x == 'sub' && i + 1 < t.length && int.tryParse(t[i + 1]) != null) {
      marcas.add('sub');
      i++;
      continue;
    }
    if (RegExp(r'^u\d\d$').hasMatch(x) || RegExp(r'^sub\d\d$').hasMatch(x)) {
      marcas.add('sub');
      continue;
    }
    if ((x == 'b' || x == 'ii') && i == t.length - 1 && i > 0) {
      marcas.add('b');
      continue;
    }
    if (marcas.contains('f') && (x == 'fem' || x == 'women' || x == 'ladies' || x == 'w')) continue;
    if (_genericas.contains(x) || x.length == 1) continue;
    palavras.add(_palavras[x] ?? x);
  }
  final junto = palavras.join(' ');
  final comum = _equipas[junto];
  return _Equipa(comum == null ? palavras : comum.split(' '), marcas);
}

/// Sem acentos, sem sufixos de clube e com as formas comuns ("FC Porto" → "porto").
String normalizarEquipa(String nome) => _equipa(nome).palavras.join(' ');

/// As duas são a mesma equipa: os nomes normalizados iguais, ou todas as palavras de um no outro
/// ("Brighton & Hove A." e "Brighton"); as reservas, sub-NN e femininas só com iguais.
bool mesmaEquipa(String a, String b) {
  final x = _equipa(a), y = _equipa(b);
  if (x.marcas.length != y.marcas.length || !x.marcas.containsAll(y.marcas)) return false;
  if (x.palavras.isEmpty || y.palavras.isEmpty) return false;
  if (x.palavras.join(' ') == y.palavras.join(' ')) return true;
  final (curta, longa) = x.palavras.length <= y.palavras.length ? (x, y) : (y, x);
  return longa.palavras.toSet().containsAll(curta.palavras);
}

// ─── títulos das grelhas ─────────────────────────────────────────────────────

class TituloEmissao {
  const TituloEmissao({this.modalidade, this.feminino = false, this.casa, this.fora, this.competicao, this.direto = false});

  /// Sem acentos e em minúsculas ('tenis', 'basquetebol'); null = sem modalidade no título.
  final String? modalidade;
  final bool feminino;
  final String? casa, fora;
  final String? competicao;
  final bool direto;
}

final _naoJogo = RegExp(
    r'fora de horas|sem transmiss|antevis|resumo|highlights|magazine|\bshow\b|compacto|\bextra\b|pre-?jogo|pos-?jogo|'
    r'estudio|noticias|reacoes|conferencia de imprensa|melhores momentos|grande jogo -|this week');

/// Lê "[Modalidade[ Fem.]: ]Casa x Fora[ - Competição][ (Direto)]" (MEO, Sport TV, EPG). Null para
/// títulos de enchimento (o nome do canal, «Fora de Horas») e programas que não são o jogo
/// (antevisões, resumos, magazines).
TituloEmissao? lerTitulo(String titulo) {
  var t = titulo.trim();
  final n = _simples(t);
  if (t.isEmpty || _naoJogo.hasMatch(n)) return null;
  if (_porAlternativo.containsKey(n.replaceAll(RegExp(r'[^a-z0-9+]'), ''))) return null;
  final direto = RegExp(r'\(\s*direto\s*\)|\bem direto\b', caseSensitive: false).hasMatch(n);
  t = t.replaceAll(RegExp(r'\s*\(\s*direto\s*\)\s*', caseSensitive: false), ' ').trim();
  var feminino = RegExp(r'\bfem\b|feminin|\bwomen\b|\(w\)').hasMatch(n);
  String? modalidade;
  final m = RegExp(r'^([^:]{2,30}):\s*').firstMatch(t);
  if (m != null && !RegExp(r'\s[xX]\s').hasMatch(m[1]!)) {
    var mod = _simples(m[1]!).trim();
    if (RegExp(r'\bfem\.?$').hasMatch(mod)) {
      feminino = true;
      mod = mod.replaceAll(RegExp(r'\s*\bfem\.?$'), '');
    }
    modalidade = mod;
    t = t.substring(m.end);
  }
  final partes = t.split(RegExp(r'\s+[xX]\s+'));
  if (partes.length == 2) {
    final i = partes[1].indexOf(' - ');
    final fora = i < 0 ? partes[1] : partes[1].substring(0, i);
    final competicao = i < 0 ? null : partes[1].substring(i + 3).trim();
    return TituloEmissao(
        modalidade: modalidade, feminino: feminino, casa: partes[0].trim(), fora: fora.trim(),
        competicao: competicao == null || competicao.isEmpty ? null : competicao, direto: direto);
  }
  return TituloEmissao(modalidade: modalidade, feminino: feminino, competicao: t.trim(), direto: direto);
}
