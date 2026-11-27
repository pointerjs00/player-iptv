import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/desporto/catalogo.dart';
import 'package:player_iptv/desporto/preferencias_jogos.dart';
import 'package:player_iptv/desporto/servico_jogos.dart';

import '../ui/jogos_apoio.dart';

/// A ordem das competições seguidas (o ecrã «Competições») e os blocos dos Jogos por ela.
void main() {
  late Directory pasta;
  setUp(() => pasta = Directory.systemTemp.createTempSync('ordem_comp'));
  tearDown(() {
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  File ficheiro() => File('${pasta.path}${Platform.pathSeparator}preferencias.json');
  List<String> seguidasDoCatalogo(Set<String> seguidas) =>
      [for (final c in catalogoCompeticoes) if (seguidas.contains(c.id)) c.id];

  test('sem ordem guardada: as seguidas pela ordem do catálogo', () async {
    final p = await PreferenciasJogos.abrir(pasta);
    expect(p.ordemCompeticoes, seguidasDoCatalogo(p.competicoes));
  });

  test('a ordem grava-se e volta ao reabrir; ids que já não existem são ignorados', () async {
    final p = await PreferenciasJogos.abrir(pasta);
    p.competicoes = {'liga-portugal', 'champions', 'premier-league'};
    p.ordemCompeticoes = ['champions', 'liga-portugal', 'premier-league'];
    await p.guardar();
    final j = jsonDecode(ficheiro().readAsStringSync()) as Map;
    ficheiro().writeAsStringSync(jsonEncode({...j, 'ordem': ['nao-existe', ...(j['ordem'] as List)]}));
    final q = await PreferenciasJogos.abrir(pasta);
    expect(q.ordemCompeticoes, ['champions', 'liga-portugal', 'premier-league']);
  });

  test('ids repetidos na ordem guardada contam uma vez', () async {
    final p = await PreferenciasJogos.abrir(pasta);
    p.competicoes = {'liga-portugal', 'champions'};
    await p.guardar();
    final j = jsonDecode(ficheiro().readAsStringSync()) as Map;
    ficheiro().writeAsStringSync(jsonEncode({...j, 'ordem': ['champions', 'liga-portugal', 'champions']}));
    final q = await PreferenciasJogos.abrir(pasta);
    expect(q.ordemCompeticoes, ['champions', 'liga-portugal']);
    q.ordemCompeticoes = ['liga-portugal', 'liga-portugal', 'champions'];
    expect(q.ordemCompeticoes, ['liga-portugal', 'champions']);
  });

  test('uma competição que se comece a seguir entra no fim', () async {
    final p = await PreferenciasJogos.abrir(pasta);
    p.competicoes = {'liga-portugal', 'champions'};
    p.ordemCompeticoes = ['champions', 'liga-portugal'];
    p.alternarCompeticao('eredivisie');
    expect(p.ordemCompeticoes, ['champions', 'liga-portugal', 'eredivisie']);
  });

  test('deixar de seguir e voltar a seguir: volta ao mesmo sítio', () async {
    final p = await PreferenciasJogos.abrir(pasta);
    p.competicoes = {'liga-portugal', 'champions', 'premier-league'};
    p.ordemCompeticoes = ['premier-league', 'champions', 'liga-portugal'];
    p.alternarCompeticao('champions');
    expect(p.ordemCompeticoes, ['premier-league', 'liga-portugal']);
    p.alternarCompeticao('champions');
    expect(p.ordemCompeticoes, ['premier-league', 'champions', 'liga-portugal']);
  });

  test('moverCompeticao muda a posição e fica dentro dos limites', () async {
    final p = await PreferenciasJogos.abrir(pasta);
    p.competicoes = {'liga-portugal', 'champions', 'premier-league'};
    p.ordemCompeticoes = ['liga-portugal', 'champions', 'premier-league'];
    p.moverCompeticao('premier-league', 0);
    expect(p.ordemCompeticoes, ['premier-league', 'liga-portugal', 'champions']);
    p.moverCompeticao('premier-league', -1);
    expect(p.ordemCompeticoes, ['premier-league', 'liga-portugal', 'champions']);
    p.moverCompeticao('liga-portugal', 9);
    expect(p.ordemCompeticoes, ['premier-league', 'champions', 'liga-portugal']);
  });

  test('ordenar por hora: desligado por omissão, e grava-se', () async {
    final p = await PreferenciasJogos.abrir(pasta);
    expect(p.ordenarPorHora, isFalse);
    p.ordenarPorHora = true;
    await p.guardar();
    expect((await PreferenciasJogos.abrir(pasta)).ordenarPorHora, isTrue);
  });

  test('os blocos dos Jogos seguem a ordem dada; as outras depois, pela do catálogo', () {
    final grupos = agruparPorCompeticao(jogosTeste(), ordem: ['eredivisie', 'premier-league']);
    expect([for (final g in grupos) g.competicao.id], ['eredivisie', 'premier-league', 'liga-portugal']);
    expect([for (final g in agruparPorCompeticao(jogosTeste())) g.competicao.id].first, 'liga-portugal');
  });
}
