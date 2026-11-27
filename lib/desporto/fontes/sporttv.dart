/// O guia oficial da Sport TV (spec §3): a página https://www.sporttv.pt/guia traz a grelha de
/// ~10 dias dentro de `<script id="__NUXT_DATA__">` (formato devalue). Cada programa tem `canal`
/// (`nome`: SPORT.TV1…7, SPORT.TV +), `descricao`, `data` (ms), `duracao` (ms), `tipoEmissao`
/// (DIRETO, Recorded, …), `modalidade` e `evento`.
library;

import 'dart:convert';

import '../../modelo/canal.dart' show semAcentos;
import '../catalogo.dart';
import '../cliente_desporto.dart';
import '../devalue.dart';
import '../modelo.dart';

const _pagina = 'https://www.sporttv.pt/guia';

final _script = RegExp(r'<script[^>]*id="__NUXT_DATA__"[^>]*>([\s\S]*?)</script>');

String _primeiraMaiuscula(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

List<Emissao> lerGuiaSportTv(String html) {
  try {
    final m = _script.firstMatch(html);
    if (m == null) return const [];
    final raiz = jsonDecode(m[1]!);
    if (raiz is! List) return const [];
    final r = <Emissao>[];
    for (var i = 0; i < raiz.length; i++) {
      final v = raiz[i];
      if (v is! Map || !v.containsKey('canal') || !v.containsKey('descricao') || !v.containsKey('data') ||
          !v.containsKey('duracao')) {
        continue;
      }
      final p = lerDevalue(raiz, i);
      if (p is! Map) continue;
      final canal = canalDaSportTv('${(p['canal'] as Map?)?['nome'] ?? ''}');
      final data = p['data'], duracao = p['duracao'];
      final descricao = '${p['descricao'] ?? ''}'.trim();
      if (canal == null || data is! num || duracao is! num || descricao.isEmpty) continue;
      final inicio = DateTime.fromMillisecondsSinceEpoch(data.toInt(), isUtc: true);
      final mod = p['modalidade'] is Map ? p['modalidade'] as Map : const {};
      final evento = p['evento'] is Map ? '${(p['evento'] as Map)['nome'] ?? ''}'.trim() : '';
      final codigo = semAcentos('${mod['codigo'] ?? mod['nomeModalidade'] ?? ''}').trim();
      final nomeMod = '${mod['nomeModalidade'] ?? ''}'.trim();
      r.add(Emissao(
        canal: canal.id,
        inicio: inicio,
        fim: inicio.add(Duration(milliseconds: duracao.toInt())),
        // no formato das outras grelhas («Modalidade: A x B - Competição»), para o casador
        titulo: [
          if (nomeMod.isNotEmpty) '${_primeiraMaiuscula(nomeMod)}: ',
          descricao,
          if (evento.isNotEmpty) ' - $evento',
        ].join(),
        direto: p['tipoEmissao'] == 'DIRETO',
        origem: 'sporttv',
        modalidade: codigo.isEmpty ? null : codigo,
        evento: evento.isEmpty ? null : evento,
      ));
    }
    return r;
  } catch (_) {
    return const [];
  }
}

Future<Lido<List<Emissao>>> guiaSportTv(ClienteDesporto c, {bool soCache = false}) async {
  final r = await c.texto('sporttv-guia', Uri.parse(_pagina), Validade.sportTv, soCache: soCache);
  return Lido.de(r, lerGuiaSportTv, const <Emissao>[]);
}
