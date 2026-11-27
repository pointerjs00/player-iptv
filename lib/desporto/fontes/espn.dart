/// ESPN (API pública do site, sem chave): o ténis (ATP e WTA) e a NBA (spec §3, fase 2).
///   ténis: https://site.api.espn.com/apis/site/v2/sports/tennis/{atp|wta}/scoreboard?dates=AAAAMMDD
///   NBA:   https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard?dates=AAAAMMDD
/// As datas são dias dos EUA (hora de Nova Iorque): um jogo às 19:30 de lá é às 00:30 do dia
/// seguinte em Lisboa. Por isso pede-se o dia escolhido e o anterior, e fica o que cai no dia de
/// Lisboa. A ESPN não diz o nível do torneio: entram os torneios todos de singulares (ver o
/// ledger do plano, Task 13).
library;

import 'dart:convert';

import '../cliente_desporto.dart';
import '../hora_lisboa.dart';
import '../modelo.dart';

const _base = 'https://site.api.espn.com/apis/site/v2/sports';

/// A Taça Davis e a Billie Jean King Cup (seleções): vão para a competição 'taca-davis'.
final _davis = RegExp(r'davis cup|billie jean king', caseSensitive: false);

DateTime? _utc(Object? s) => s is String ? DateTime.tryParse(s)?.toUtc() : null;

Map<String, dynamic> _mapa(Object? o) => o is Map<String, dynamic> ? o : const {};

List<Map<String, dynamic>> _lista(Object? o) => o is List ? o.whereType<Map<String, dynamic>>().toList() : const [];

EstadoJogo _estado(Map<String, dynamic> tipo) {
  final nome = '${tipo['name'] ?? ''}';
  if (nome.contains('POSTPONED') || nome.contains('SUSPENDED') || nome.contains('DELAYED')) return EstadoJogo.adiado;
  if (nome.contains('CANCEL')) return EstadoJogo.cancelado;
  if (nome.contains('HALFTIME')) return EstadoJogo.intervalo;
  return switch (tipo['state']) {
    'in' => EstadoJogo.aoVivo,
    'post' => EstadoJogo.terminado,
    _ => EstadoJogo.agendado,
  };
}

Map<String, dynamic> _tipoEstado(Map<String, dynamic> c) => _mapa(_mapa(c['status'])['type']);

/// Os jogos de singulares de um torneio da `tour` ('atp' ou 'wta') em `texto` (a resposta do
/// scoreboard), das competições `seguidas`.
List<Jogo> lerTenisEspn(String texto, String tour, Set<String> seguidas) {
  try {
    final r = <Jogo>[];
    for (final ev in _lista(_mapa(jsonDecode(texto))['events'])) {
      final torneio = '${ev['name'] ?? ''}';
      final comp = _davis.hasMatch(torneio) ? 'taca-davis' : tour;
      if (!seguidas.contains(comp)) continue;
      for (final g in _lista(ev['groupings'])) {
        final grupo = '${_mapa(g['grouping'])['displayName'] ?? ''}';
        if (RegExp('doubles', caseSensitive: false).hasMatch(grupo)) continue;
        for (final c in _lista(g['competitions'])) {
          final cs = _lista(c['competitors']);
          final a = cs.where((x) => x['homeAway'] == 'home').firstOrNull ?? cs.firstOrNull;
          final b = cs.where((x) => x['homeAway'] == 'away').firstOrNull ?? cs.elementAtOrNull(1);
          final nomeA = '${_mapa(a?['athlete'])['displayName'] ?? ''}';
          final nomeB = '${_mapa(b?['athlete'])['displayName'] ?? ''}';
          final inicio = _utc(c['date']);
          if (c['id'] == null || inicio == null || nomeA.isEmpty || nomeB.isEmpty) continue;
          final tipo = _tipoEstado(c);
          final estado = _estado(tipo);
          // o resultado em sets ganhos («2–1»)
          final la = _lista(a?['linescores']), lb = _lista(b?['linescores']);
          var sa = 0, sb = 0;
          for (var i = 0; i < la.length && i < lb.length; i++) {
            final x = (la[i]['value'] as num?) ?? 0, y = (lb[i]['value'] as num?) ?? 0;
            if (x > y) sa++;
            if (y > x) sb++;
          }
          r.add(Jogo(
            id: 'espn:$tour:${c['id']}',
            desporto: Desporto.tenis,
            competicaoId: comp,
            casa: nomeA,
            fora: nomeB,
            inicio: inicio,
            estado: estado,
            resultado: estado == EstadoJogo.agendado ? null : '$sa–$sb',
            minuto: estado == EstadoJogo.aoVivo ? tipo['shortDetail'] as String? : null,
            ronda: _mapa(c['round'])['displayName'] as String?,
            feminino: tour == 'wta',
            torneio: torneio,
          ));
        }
      }
    }
    return r;
  } catch (_) {
    return const [];
  }
}

/// Os jogos da NBA em `texto` (a resposta do scoreboard), se a NBA for `seguida`.
List<Jogo> lerNbaEspn(String texto, Set<String> seguidas) {
  if (!seguidas.contains('nba')) return const [];
  try {
    final r = <Jogo>[];
    for (final ev in _lista(_mapa(jsonDecode(texto))['events'])) {
      final c = _lista(ev['competitions']).firstOrNull;
      if (c == null) continue;
      final cs = _lista(c['competitors']);
      final casa = cs.where((x) => x['homeAway'] == 'home').firstOrNull;
      final fora = cs.where((x) => x['homeAway'] == 'away').firstOrNull;
      final tc = _mapa(casa?['team']), tf = _mapa(fora?['team']);
      final inicio = _utc(ev['date']);
      if (ev['id'] == null || inicio == null || tc['displayName'] == null || tf['displayName'] == null) continue;
      final tipo = _tipoEstado(c);
      final estado = _estado(tipo);
      final comecou = estado == EstadoJogo.aoVivo || estado == EstadoJogo.intervalo || estado == EstadoJogo.terminado;
      r.add(Jogo(
        id: 'espn:nba:${ev['id']}',
        desporto: Desporto.basquetebol,
        competicaoId: 'nba',
        casa: '${tc['displayName']}',
        fora: '${tf['displayName']}',
        casaCurto: tc['abbreviation'] as String?,
        foraCurto: tf['abbreviation'] as String?,
        emblemaCasa: tc['logo'] as String?,
        emblemaFora: tf['logo'] as String?,
        inicio: inicio,
        estado: estado,
        resultado: comecou ? '${casa?['score'] ?? 0}–${fora?['score'] ?? 0}' : null,
        minuto: estado == EstadoJogo.aoVivo ? tipo['shortDetail'] as String? : null,
      ));
    }
    return r;
  } catch (_) {
    return const [];
  }
}

bool _noDia(DateTime utc, DateTime dia) {
  final l = utcParaLisboa(utc);
  return l.year == dia.year && l.month == dia.month && l.day == dia.day;
}

/// Os jogos da ESPN do dia `dia` (de Lisboa) das competições `seguidas`.
/// `validade` muda a da cache (o ao vivo pede de novo ao fim de um minuto).
Future<Lido<List<Jogo>>> jogosEspn(ClienteDesporto c, DateTime dia, Set<String> seguidas,
    {bool soCache = false, Duration? validade}) async {
  final davis = seguidas.contains('taca-davis');
  final pedidos = <(String, String, List<Jogo> Function(String))>[
    if (seguidas.contains('atp') || davis) ('tennis/atp', 'atp', (t) => lerTenisEspn(t, 'atp', seguidas)),
    if (seguidas.contains('wta') || davis) ('tennis/wta', 'wta', (t) => lerTenisEspn(t, 'wta', seguidas)),
    if (seguidas.contains('nba')) ('basketball/nba', 'nba', (t) => lerNbaEspn(t, seguidas)),
  ];
  if (pedidos.isEmpty) return const Lido(<Jogo>[]);
  final hoje = utcParaLisboa(c.agora());
  final eHoje = hoje.year == dia.year && hoje.month == dia.month && hoje.day == dia.day;
  final dias = [DateTime(dia.year, dia.month, dia.day - 1), dia];
  final lidos = await Future.wait([
    for (final (caminho, nome, ler) in pedidos)
      for (final d in dias)
        c
            .texto('espn-$nome-${diaTexto(d)}', Uri.parse('$_base/$caminho/scoreboard?dates=${diaTexto(d)}'),
                validade ?? (eHoje ? Validade.espnHoje : Validade.jogosOutrosDias),
                soCache: soCache)
            .then((r) => Lido.de(r, ler, const <Jogo>[])),
  ]);
  final vistos = <String>{};
  final jogos = [
    for (final l in lidos)
      for (final j in l.dados)
        if (_noDia(j.inicio, dia) && vistos.add(j.id)) j,
  ];
  DateTime? data;
  for (final l in lidos) {
    final d = l.data;
    if (d != null && (data == null || d.isBefore(data))) data = d;
  }
  return Lido(jogos, data: data, velho: lidos.any((l) => l.velho));
}
