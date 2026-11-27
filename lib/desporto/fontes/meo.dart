/// A grelha da MEO: os programas de um canal num dia (spec §3).
///   https://meogouser.apps.meo.pt/Services/GridTv/GridTv.svc/GetLiveChannelProgramsByDate
///     ?callLetter=SPT1HD&date=AAAA-MM-DD&userAgent=IPTV_OFR_GTV
/// As horas vêm sem fuso (hora de Lisboa). Ficam de fora os títulos de enchimento e os programas
/// que não são o jogo (antevisões, resumos, magazines): ver [lerTitulo].
library;

import 'dart:convert';

import '../cliente_desporto.dart';
import '../hora_lisboa.dart';
import '../modelo.dart';
import '../nomes.dart';

const _base = 'https://meogouser.apps.meo.pt/Services/GridTv/GridTv.svc/GetLiveChannelProgramsByDate';

List<Emissao> lerGrelhaMeo(String texto, CanalTv canal) {
  try {
    final j = jsonDecode(texto);
    if (j is! Map || j['Status'] != 'OK' || j['Result'] is! List) return const [];
    final r = <Emissao>[];
    for (final p in (j['Result'] as List).whereType<Map>()) {
      final titulo = '${p['Title'] ?? ''}'.trim();
      final inicio = lerHoraLisboa(p['StartDate']), fim = lerHoraLisboa(p['EndDate']);
      if (inicio == null || fim == null || p['IsAdultContent'] == true) continue;
      final t = lerTitulo(titulo);
      if (t == null) continue;
      r.add(Emissao(
        canal: canal.id,
        inicio: inicio,
        fim: fim,
        titulo: titulo,
        // sem «(Direto)» a MEO não diz (a DAZN nem sempre marca)
        direto: t.direto ? true : null,
        origem: 'meo',
        modalidade: t.modalidade,
        evento: t.competicao,
      ));
    }
    return r;
  } catch (_) {
    return const [];
  }
}

/// A grelha de `canal` no dia `dia` (dia de calendário em Lisboa).
Future<Lido<List<Emissao>>> grelhaMeo(ClienteDesporto c, CanalTv canal, DateTime dia, {bool soCache = false}) async {
  final letras = canal.meo;
  if (letras == null) return const Lido(<Emissao>[]);
  final uri = Uri.parse(_base).replace(queryParameters: {
    'callLetter': letras,
    'date': diaTexto(dia, '-'),
    'userAgent': 'IPTV_OFR_GTV',
  });
  final r = await c.texto('meo-$letras-${diaTexto(dia)}', uri, Validade.meo, soCache: soCache);
  return Lido.de(r, (t) => lerGrelhaMeo(t, canal), const <Emissao>[]);
}
