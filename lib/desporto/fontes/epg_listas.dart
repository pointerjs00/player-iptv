/// A programação dos canais portugueses tirada das próprias listas do utilizador (Xtream e portal
/// MAC): para cada canal do catálogo, a grelha do dia numa das listas que o têm. Cobre os canais
/// que as outras fontes não têm (BTV, Sporting TV, Porto Canal…). As listas M3U não têm guia.
library;

import 'dart:convert';

import '../../dados/biblioteca.dart';
import '../../modelo/canal.dart';
import '../../modelo/conta.dart';
import '../../protocolos/protocolo.dart';
import '../../protocolos/stalker.dart';
import '../../protocolos/xtream.dart';
import '../catalogo.dart';
import '../cliente_desporto.dart';
import '../hora_lisboa.dart';
import '../modelo.dart';
import '../onde_ver.dart';

/// Um programa da grelha de um canal (horas em UTC).
typedef ProgramaEpg = ({DateTime inicio, DateTime fim, String titulo});

/// A grelha de `canal` (da lista com a `conta`) à volta do dia `dia`.
typedef ObterEpgCanal = Future<List<ProgramaEpg>> Function(Conta conta, Canal canal, DateTime dia);

/// Quanto vale a grelha guardada de um canal.
const validadeEpgListas = Duration(hours: 6);

/// As listas a experimentar por canal (a primeira que der a grelha serve).
const fontesPorCanal = 2;

DateTime? _hora(Object? v) {
  final n = v is num ? v.toInt() : int.tryParse('${v ?? ''}'.trim());
  return n == null || n <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(n * 1000, isUtc: true);
}

String _deBase64(String t) {
  final s = t.trim();
  try {
    return utf8.decode(base64.decode(base64.normalize(s)));
  } on FormatException {
    return s;
  }
}

List<ProgramaEpg> _ler(Iterable<Object?> itens, {required String titulo, bool base64 = false}) => [
      for (final x in itens)
        if (x is Map)
          if ((_hora(x['start_timestamp']), _hora(x['stop_timestamp'] ?? x['end_timestamp'])) case (final i?, final f?))
            if (f.isAfter(i))
              if ((base64 ? _deBase64('${x[titulo] ?? ''}') : '${x[titulo] ?? ''}').trim() case final t when t.isNotEmpty)
                (inicio: i, fim: f, titulo: t),
    ];

/// A resposta do `get_simple_data_table` do Xtream (`epg_listings`, títulos em base64).
List<ProgramaEpg> lerEpgXtream(Object? r) {
  final l = r is Map ? r['epg_listings'] : null;
  return l is List ? _ler(l, titulo: 'title', base64: true) : const [];
}

/// A resposta do `get_simple_data_table` do portal MAC (`js.data`, ou só `data`).
List<ProgramaEpg> lerEpgStalker(Object? r) {
  var d = r;
  if (d is Map && d['js'] != null) d = d['js'];
  if (d is Map && d['data'] != null) d = d['data'];
  return d is List ? _ler(d, titulo: 'name') : const [];
}

/// Pede a grelha ao servidor da lista.
Future<List<ProgramaEpg>> obterEpgDaLista(Conta conta, Canal canal, DateTime dia) async => switch (conta.tipo) {
      Tipo.xtream => lerEpgXtream(await Xtream.api(conta, {'action': 'get_simple_data_table', 'stream_id': canal.id}, null,
          timeout: const Duration(seconds: 20))),
      Tipo.stalker => lerEpgStalker(await (Protocolo.para(conta) as Stalker).pedir(conta, {
          'type': 'epg',
          'action': 'get_simple_data_table',
          'ch_id': canal.id,
          'date': diaTexto(dia, '-'),
          'p': '1',
        }, timeout: const Duration(seconds: 20))),
      Tipo.m3u => const [],
    };

Map<String, Object> _paraJson(ProgramaEpg p) =>
    {'i': p.inicio.toIso8601String(), 'f': p.fim.toIso8601String(), 't': p.titulo};

ProgramaEpg? _deJson(Object? j) {
  if (j is! Map) return null;
  final i = DateTime.tryParse('${j['i']}'), f = DateTime.tryParse('${j['f']}');
  return i == null || f == null ? null : (inicio: i.toUtc(), fim: f.toUtc(), titulo: '${j['t']}');
}

bool _temGuia(Lista l) => l.conta.tipo != Tipo.m3u;

/// As emissões dos canais do catálogo no dia `dia`, a partir das listas. Por canal experimenta até
/// [fontesPorCanal] listas, pela ordem do «Onde ver» (4 canais de cada vez); guarda a grelha em
/// cache. Com `soCache` (dados móveis) não pede nada. Se todos os pedidos falharem, lança o erro
/// (a fonte falhou).
Future<Lido<List<Emissao>>> grelhaDasListas(ClienteDesporto cliente, FontesDosCanais fontes, DateTime dia,
    {ObterEpgCanal obter = obterEpgDaLista, bool soCache = false, Iterable<CanalTv>? canais}) async {
  // o dia de Lisboa, e as primeiras horas do seguinte (os jogos que acabam depois da meia-noite)
  final desde = lisboaParaUtc(DateTime.utc(dia.year, dia.month, dia.day));
  final ate = lisboaParaUtc(DateTime.utc(dia.year, dia.month, dia.day + 1, 6));
  final direto = RegExp(r'\b(direto|live|ao vivo)\b', caseSensitive: false);
  Object? erro;
  var algum = false;
  DateTime? velhoDesde;

  Future<List<Emissao>> umCanal(CanalTv canal) async {
    final fs = ordenarFontes(fontes.fontes(canal.id)).where((f) => _temGuia(f.lista)).take(fontesPorCanal);
    for (final f in fs) {
      final chave = 'epg-${f.lista.id}-${f.canal.id}-${diaTexto(dia)}';
      final g = await cliente.armazem.ler(chave);
      final agora = cliente.agora();
      List<ProgramaEpg>? ps;
      if (g != null && (soCache || agora.difference(g.data) < validadeEpgListas)) {
        ps = (jsonDecode(g.texto) as List).map(_deJson).whereType<ProgramaEpg>().toList();
        final v = velhoDesde;
        if (agora.difference(g.data) >= validadeEpgListas && (v == null || g.data.isBefore(v))) velhoDesde = g.data;
      } else if (!soCache) {
        try {
          ps = await obter(f.lista.conta, f.canal, dia);
          await cliente.armazem.gravar(chave, jsonEncode([for (final p in ps) _paraJson(p)]), agora);
        } catch (e) {
          erro ??= e;
          continue; // a lista seguinte
        }
      }
      if (ps == null) continue;
      algum = true;
      final doDia = [for (final p in ps) if (p.fim.isAfter(desde) && p.inicio.isBefore(ate)) p];
      if (doDia.isEmpty) continue; // esta lista não tem a grelha deste dia: experimenta outra
      return [
        for (final p in doDia)
          Emissao(
            canal: canal.id,
            inicio: p.inicio,
            fim: p.fim,
            titulo: p.titulo,
            origem: 'epg',
            direto: direto.hasMatch(p.titulo) ? true : null,
          ),
      ];
    }
    return const [];
  }

  final lista = [...canais ?? catalogoCanais];
  final r = <Emissao>[];
  for (var i = 0; i < lista.length; i += 4) {
    for (final es in await Future.wait([for (final c in lista.skip(i).take(4)) umCanal(c)])) {
      r.addAll(es);
    }
  }
  if (!algum && erro != null) throw erro!;
  return Lido(r, data: velhoDesde ?? cliente.agora(), velho: velhoDesde != null);
}
