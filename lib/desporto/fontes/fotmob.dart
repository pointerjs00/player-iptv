/// FotMob: os jogos de futebol do dia e o guia de TV de Portugal (spec §3).
///   jogos: https://www.fotmob.com/api/data/matches?date=AAAAMMDD&timezone=Europe/Lisbon&ccode3=PRT
///   guia:  https://www.fotmob.com/api/data/tvguide?country=pt&timezone=Europe/Lisbon
/// As competições reconhecem-se pelo `primaryId` (o `id` muda por época ou fase).
library;

import 'dart:convert';

import '../../modelo/canal.dart' show semAcentos;
import '../catalogo.dart';
import '../cliente_desporto.dart';
import '../modelo.dart';

const _base = 'https://www.fotmob.com/api/data';

/// O emblema de uma equipa (a confirmar no aparelho).
/// O logótipo de uma competição (pelo `primaryId`; o mesmo esquema dos emblemas, a confirmar).
String logoCompeticaoFotmob(int primaryId) =>
    'https://images.fotmob.com/image_resources/logo/leaguelogo/$primaryId.png';

String emblemaFotmob(Object id) => 'https://images.fotmob.com/image_resources/logo/teamlogo/${id}_small.png';

Competicao? _competicao(Map<String, dynamic> liga, Set<String> seguidas) {
  final primario = liga['primaryId'] ?? liga['leagueId'] ?? liga['id'];
  final nome = semAcentos('${liga['name'] ?? liga['leagueName'] ?? ''}');
  final pais = '${liga['ccode'] ?? liga['leagueCcode'] ?? ''}';
  for (final c in catalogoCompeticoes) {
    if (!seguidas.contains(c.id) || c.desporto != Desporto.futebol) continue;
    if (c.fotmob != null && c.fotmob == primario) return c;
    final padrao = c.fotmobNome;
    if (padrao != null && RegExp(padrao).hasMatch(nome) && (c.fotmobPais == null || c.fotmobPais == pais)) return c;
  }
  return null;
}

/// Tira os caracteres de direção do texto e a aspa curva do minuto.
/// Os caracteres de direção do texto (U+200E, U+200F, U+202A–U+202E, U+2066–U+2069).
final _invisiveis = RegExp('[${String.fromCharCodes([0x200e, 0x200f])}${String.fromCharCode(0x202a)}-'
    '${String.fromCharCode(0x202e)}${String.fromCharCode(0x2066)}-${String.fromCharCode(0x2069)}]');

String _limpar(String s) => s.replaceAll(_invisiveis, '').replaceAll(String.fromCharCode(0x2019), "'").trim();

DateTime? _utc(Object? s) => s is String ? DateTime.tryParse(s)?.toUtc() : null;

Jogo? _jogo(Map<String, dynamic> m, Competicao comp) {
  final casa = m['home'], fora = m['away'];
  final st = m['status'];
  if (casa is! Map || fora is! Map) return null;
  final status = st is Map ? st : const {};
  final inicio = _utc(status['utcTime'] ?? m['utcTime']);
  if (inicio == null) return null;
  final comecou = status['started'] == true, acabou = status['finished'] == true;
  final vivo = status['liveTime'] is Map ? _limpar('${(status['liveTime'] as Map)['short'] ?? ''}') : '';
  final estado = status['cancelled'] == true
      ? EstadoJogo.cancelado
      : acabou
          ? EstadoJogo.terminado
          : comecou
              ? (RegExp(r'^(ht|int|intervalo|pause)', caseSensitive: false).hasMatch(vivo)
                  ? EstadoJogo.intervalo
                  : EstadoJogo.aoVivo)
              : EstadoJogo.agendado;
  final nomeCasa = '${casa['name'] ?? ''}', nomeFora = '${fora['name'] ?? ''}';
  return Jogo(
    id: 'fotmob:${m['id']}',
    desporto: Desporto.futebol,
    competicaoId: comp.id,
    casa: nomeCasa,
    fora: nomeFora,
    casaCurto: casa['shortName'] as String?,
    foraCurto: fora['shortName'] as String?,
    emblemaCasa: casa['id'] == null ? null : emblemaFotmob(casa['id'] as Object),
    emblemaFora: fora['id'] == null ? null : emblemaFotmob(fora['id'] as Object),
    inicio: inicio,
    estado: estado,
    resultado: comecou || acabou ? '${casa['score'] ?? 0}–${fora['score'] ?? 0}' : null,
    minuto: estado == EstadoJogo.aoVivo && vivo.isNotEmpty ? vivo : null,
    ronda: m['tournamentStage'] as String?,
    feminino: RegExp(r'\(W\)').hasMatch(nomeCasa) || RegExp(r'\(W\)').hasMatch(nomeFora),
  );
}

/// Os jogos de `texto` (a resposta de `matches`) das competições `seguidas` (ids do catálogo).
List<Jogo> lerJogosFotmob(String texto, Set<String> seguidas) {
  try {
    final j = jsonDecode(texto);
    final ligas = j is Map ? j['leagues'] : null;
    if (ligas is! List) return const [];
    final r = <Jogo>[];
    for (final l in ligas.whereType<Map<String, dynamic>>()) {
      final comp = _competicao(l, seguidas);
      final ms = l['matches'];
      if (comp == null || ms is! List) continue;
      for (final m in ms.whereType<Map<String, dynamic>>()) {
        final jogo = _jogo(m, comp);
        if (jogo != null) r.add(jogo);
      }
    }
    return r;
  } catch (_) {
    return const [];
  }
}

/// As emissões do guia de TV de Portugal, cada uma com o id do jogo (só os canais do catálogo).
List<(String, Emissao)> lerGuiaFotmob(String texto) {
  try {
    final j = jsonDecode(texto);
    if (j is! Map) return const [];
    final r = <(String, Emissao)>[];
    for (final dia in j.values.whereType<List>()) {
      for (final l in dia.whereType<Map>()) {
        final ms = l['matches'];
        if (ms is! List) continue;
        for (final m in ms.whereType<Map>()) {
          final inicio = _utc(m['utcTime']);
          final cs = m['channels'];
          if (inicio == null || cs is! List) continue;
          final titulo = '${(m['home'] as Map?)?['name'] ?? ''} x ${(m['away'] as Map?)?['name'] ?? ''}';
          final vistos = <String>{};
          for (final c in cs.whereType<Map>()) {
            final canal = canalDoFotmob('${c['name'] ?? ''}');
            if (canal == null || !vistos.add(canal.id)) continue;
            r.add(('fotmob:${m['id']}', Emissao(
              canal: canal.id,
              inicio: inicio,
              fim: inicio.add(const Duration(hours: 2)),
              titulo: titulo,
              direto: true,
              origem: 'fotmob',
            )));
          }
        }
      }
    }
    return r;
  } catch (_) {
    return const [];
  }
}

/// Os jogos do dia `dia` (dia de calendário em Lisboa).
/// `validade` muda a da cache (o ao vivo pede de novo ao fim de um minuto).
Future<Lido<List<Jogo>>> jogosFotmob(ClienteDesporto c, DateTime dia, Set<String> seguidas,
    {bool soCache = false, Duration? validade}) async {
  final hoje = c.agora().toLocal();
  final eHoje = hoje.year == dia.year && hoje.month == dia.month && hoje.day == dia.day;
  final uri = Uri.parse('$_base/matches').replace(queryParameters: {
    'date': diaTexto(dia),
    'timezone': 'Europe/Lisbon',
    'ccode3': 'PRT',
  });
  final r = await c.texto(
      'fotmob-jogos-${diaTexto(dia)}', uri, validade ?? (eHoje ? Validade.jogosHoje : Validade.jogosOutrosDias),
      soCache: soCache);
  return Lido.de(r, (t) => lerJogosFotmob(t, seguidas), const <Jogo>[]);
}

/// O guia de TV de Portugal (7 dias num pedido).
Future<Lido<List<(String, Emissao)>>> guiaTvFotmob(ClienteDesporto c, {bool soCache = false}) async {
  final uri = Uri.parse('$_base/tvguide').replace(queryParameters: {'country': 'pt', 'timezone': 'Europe/Lisbon'});
  final r = await c.texto('fotmob-guia-pt', uri, Validade.guiaFotmob, soCache: soCache);
  return Lido.de(r, lerGuiaFotmob, const <(String, Emissao)>[]);
}
