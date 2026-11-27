import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/desporto/armazem_desporto.dart';
import 'package:player_iptv/desporto/cliente_desporto.dart';
import 'package:player_iptv/desporto/modelo.dart';
import 'package:player_iptv/desporto/preferencias_jogos.dart';
import 'package:player_iptv/desporto/servico_jogos.dart';

/// O serviço que junta os jogos do FotMob com as grelhas, com um cliente HTTP falso que responde
/// com as respostas gravadas de 27/11/2026.
void main() {
  String resposta(String n) => File('test/desporto/respostas/$n').readAsStringSync();
  final jogos27 = resposta('fotmob-matches-20261127.json');
  final guia = resposta('fotmob-tvguide-pt.json');
  final sporttv = resposta('sporttv-guia.html');
  final meoSpt1 = resposta('meo-SPT1HD-2026-11-27.json');
  final meoDazn2 = resposta('meo-DAZN2-2026-11-27.json');
  const meoVazia = '{"Status":"OK","Result":[]}';
  final dia27 = DateTime(2026, 11, 27), dia28 = DateTime(2026, 11, 28);

  late Directory pasta;
  late DateTime agora;
  late List<Uri> pedidos;
  late Set<String> semRede; // anfitriões que falham
  late ServicoJogos servico;

  Future<String> obter(Uri u, Map<String, String> _) async {
    pedidos.add(u);
    if (semRede.contains(u.host) || semRede.contains('*')) throw const SocketException('sem rede');
    if (u.host.contains('fotmob')) {
      if (u.path.endsWith('/tvguide')) return guia;
      return u.queryParameters['date'] == '20261127' ? jogos27 : '{"leagues":[]}';
    }
    if (u.host.contains('meo')) {
      if (u.queryParameters['date'] != '2026-11-27') return meoVazia;
      return switch (u.queryParameters['callLetter']) { 'SPT1HD' => meoSpt1, 'DAZN2' => meoDazn2, _ => meoVazia };
    }
    if (u.host.contains('sporttv')) return sporttv;
    throw StateError('pedido inesperado: ${u.host}');
  }

  setUp(() async {
    pasta = Directory.systemTemp.createTempSync('servico_jogos');
    agora = DateTime.utc(2026, 11, 27, 19);
    pedidos = [];
    semRede = {};
    final armazem = await ArmazemDesporto.abrir(pasta);
    final prefs = await PreferenciasJogos.abrir(pasta);
    servico = ServicoJogos(ClienteDesporto(armazem, obter: obter, agora: () => agora), prefs);
  });
  tearDown(() => pasta.deleteSync(recursive: true));

  JogoComCanais jogo(List<JogoComCanais> js, String casa) => js.singleWhere((j) => j.jogo.casa == casa);

  test('com a MEO a dar erro, os jogos e os canais do FotMob aparecem e o estado diz que a MEO falhou', () async {
    semRede = {'meogouser.apps.meo.pt'};
    await servico.carregar(dia27);
    expect(servico.estado.carga, Carga.pronto);
    expect(servico.estado.falhas, {FonteJogos.meo});
    expect(nomeFonte(FonteJogos.meo), 'MEO');
    final js = servico.jogos(FiltroJogos(dia27, soComCanal: false));
    expect(js, isNotEmpty);
    final m = jogo(js, 'Marítimo');
    expect(m.canais.map((t) => t.canal), contains('sporttv1'));
    expect(m.canais.first.confianca, Confianca.confirmado);
  });

  test('sem rede e com a cache de há 2 h: os jogos ficam, marcados como velhos com a data', () async {
    await servico.carregar(dia27);
    expect(servico.estado.velho, isFalse);
    final antes = servico.jogos(FiltroJogos(dia27, soComCanal: false)).length;
    agora = agora.add(const Duration(hours: 2));
    semRede = {'*'};
    await servico.carregar(dia27);
    expect(servico.estado.falhas, isEmpty, reason: 'havia cache: não é uma falha');
    expect(servico.estado.velho, isTrue);
    expect(servico.estado.velhoDesde, DateTime.utc(2026, 11, 27, 19));
    expect(servico.jogos(FiltroJogos(dia27, soComCanal: false)), hasLength(antes));
  });

  test('os filtros: só com canal, só em direto, por competição e por desporto', () async {
    await servico.carregar(dia27);
    final todos = servico.jogos(FiltroJogos(dia27, soComCanal: false));
    final comCanal = servico.jogos(FiltroJogos(dia27));
    expect(comCanal.length, lessThan(todos.length));
    expect(comCanal.every((j) => j.canais.isNotEmpty), isTrue);
    final direto = servico.jogos(FiltroJogos(dia27, soDireto: true, soComCanal: false));
    expect(direto, isNotEmpty);
    expect(direto.every((j) => j.jogo.aDecorrer), isTrue);
    expect(direto.map((j) => j.jogo.casa), contains('Marítimo'));
    final liga = servico.jogos(FiltroJogos(dia27, competicoes: {'liga-portugal'}, soComCanal: false));
    expect(liga, isNotEmpty);
    expect(liga.every((j) => j.jogo.competicaoId == 'liga-portugal'), isTrue);
    expect(servico.jogos(FiltroJogos(dia27, desporto: Desporto.tenis, soComCanal: false)), isEmpty);
    expect(servico.jogos(FiltroJogos(dia28, soComCanal: false)), isEmpty, reason: 'dia ainda não carregado');
    // pela hora
    final horas = todos.map((j) => j.jogo.inicio).toList();
    expect(horas, [...horas]..sort());
  });

  test('a pesquisa por equipa: parte do nome, sem acentos nem maiúsculas, nas duas equipas', () async {
    await servico.carregar(dia27);
    List<String> casas(String q) =>
        [for (final j in servico.jogos(FiltroJogos(dia27, soComCanal: false, equipa: q))) j.jogo.casa];
    expect(casas('maritimo'), ['Marítimo']);
    expect(casas('NACION'), ['Marítimo'], reason: 'também a equipa de fora');
    expect(casas('  '), hasLength(servico.jogos(FiltroJogos(dia27, soComCanal: false)).length));
    expect(casas('zzz'), isEmpty);
  });

  test('por competição: pela ordem do catálogo, e os jogos de cada uma pela hora', () async {
    await servico.carregar(dia27);
    final grupos = agruparPorCompeticao(servico.jogos(FiltroJogos(dia27, soComCanal: false)));
    final ids = [for (final g in grupos) g.competicao.id];
    expect(ids.first, 'liga-portugal');
    expect(ids.toSet(), hasLength(ids.length), reason: 'uma vez cada');
    for (final g in grupos) {
      expect(g.jogos.every((j) => j.jogo.competicaoId == g.competicao.id), isTrue);
      final horas = [for (final j in g.jogos) j.jogo.inicio];
      expect(horas, [...horas]..sort());
    }
  });

  test('mudar de dia e voltar não pede de novo o que está na cache', () async {
    await servico.carregar(dia27);
    await servico.carregar(dia28);
    final n = pedidos.length;
    await servico.carregar(dia27);
    expect(pedidos.length, n, reason: 'tudo do dia 27 ainda vale');
    expect(servico.jogos(FiltroJogos(dia27, soComCanal: false)), isNotEmpty);
  });

  test('em dados móveis, sem forçar, só o guia do FotMob vai à rede', () async {
    final armazem = await ArmazemDesporto.abrir(pasta);
    final prefs = await PreferenciasJogos.abrir(pasta);
    final movel = ServicoJogos(ClienteDesporto(armazem, obter: obter, agora: () => agora), prefs,
        emDadosMoveis: () async => true);
    await movel.carregar(dia27);
    expect(pedidos.map((u) => u.host).toSet(), {'www.fotmob.com'});
    expect(pedidos.single.path, endsWith('/tvguide'));
    pedidos.clear();
    await movel.carregar(dia27, forcar: true);
    expect(pedidos.map((u) => u.host).toSet(), containsAll(['www.fotmob.com', 'meogouser.apps.meo.pt', 'www.sporttv.pt']));
  });
}
