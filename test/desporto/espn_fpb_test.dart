import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/desporto/armazem_desporto.dart';
import 'package:player_iptv/desporto/casador.dart';
import 'package:player_iptv/desporto/cliente_desporto.dart';
import 'package:player_iptv/desporto/fontes/espn.dart';
import 'package:player_iptv/desporto/fontes/fpb.dart';
import 'package:player_iptv/desporto/modelo.dart';

/// Fase 2 (plano dos Jogos, Task 13): ténis e NBA (ESPN) e a Liga Betclic (FPB), com respostas
/// reais recortadas (27/11/2026).
void main() {
  String resposta(String n) => File('test/desporto/respostas/$n').readAsStringSync();
  final wta = resposta('espn-wta-20261127.json');
  final nba = resposta('espn-nba-20261127.json');
  final fpb = resposta('fpb-calendario.html');

  group('ténis (ESPN)', () {
    test('só os singulares, como jogos da WTA com o torneio e as duas jogadoras', () {
      final js = lerTenisEspn(wta, 'wta', {'wta'});
      expect(js, hasLength(2), reason: 'os pares ficam de fora');
      final j = js.firstWhere((j) => j.casa == 'Carole Monnet' || j.fora == 'Carole Monnet');
      expect({j.casa, j.fora}, {'Carole Monnet', 'Veronika Erjavec'});
      expect(j.competicaoId, 'wta');
      expect(j.desporto, Desporto.tenis);
      expect(j.feminino, isTrue);
      expect(j.torneio, 'IEB+ Argentina Open');
      expect(j.inicio, DateTime.utc(2026, 11, 27, 18));
      expect(j.estado, EstadoJogo.agendado);
      expect(js.every((j) => !j.casa.contains('/')), isTrue);
    });

    test('sem seguir a WTA não há jogos', () {
      expect(lerTenisEspn(wta, 'wta', {'atp'}), isEmpty);
    });

    test('a Taça Davis e a BJK Cup vão para a competição delas (se seguida)', () {
      final davis = wta.replaceAll('IEB+ Argentina Open', 'Billie Jean King Cup Finals');
      expect(lerTenisEspn(davis, 'wta', {'wta'}), isEmpty, reason: 'não é um torneio da WTA');
      expect(lerTenisEspn(davis, 'wta', {'taca-davis'}).map((j) => j.competicaoId).toSet(), {'taca-davis'});
    });

    test('um torneio na grelha da Sport TV fica Possível para os jogos dele', () {
      final j = lerTenisEspn(wta, 'wta', {'wta'}).first;
      final t = casar([j], [
        Emissao(
            canal: 'sporttv4',
            inicio: DateTime.utc(2026, 11, 27, 17),
            fim: DateTime.utc(2026, 11, 27, 22),
            titulo: 'Ténis: IEB+ Argentina Open',
            origem: 'sporttv',
            direto: true,
            modalidade: 'Ténis',
            evento: 'IEB+ Argentina Open'),
      ]);
      expect(t.single.canal, 'sporttv4');
      expect(t.single.confianca, Confianca.possivel);
    });
  });

  group('NBA (ESPN)', () {
    test('as equipas, a hora UTC e os emblemas', () {
      final js = lerNbaEspn(nba, {'nba'});
      expect(js, hasLength(3));
      final j = js.firstWhere((j) => j.casa == 'Indiana Pacers');
      expect(j.fora, 'Philadelphia 76ers');
      expect(j.inicio, DateTime.utc(2026, 11, 28, 0, 30));
      expect(j.desporto, Desporto.basquetebol);
      expect(j.competicaoId, 'nba');
      expect(j.emblemaCasa, isNotNull);
      expect(j.resultado, isNull, reason: 'ainda não começou');
      expect(lerNbaEspn(nba, {'lpb'}), isEmpty);
    });

    test('um jogo às 00:30 UTC aparece no dia certo de Lisboa (pede também o dia anterior dos EUA)', () async {
      final pasta = Directory.systemTemp.createTempSync('espn');
      addTearDown(() => pasta.deleteSync(recursive: true));
      final pedidos = <String>[];
      final c = ClienteDesporto(await ArmazemDesporto.abrir(pasta),
          agora: () => DateTime.utc(2026, 11, 27, 12),
          obter: (u, _) async {
            pedidos.add('${u.path} ${u.queryParameters['dates']}');
            return u.queryParameters['dates'] == '20261127' ? nba : '{"events":[]}';
          });
      final dia28 = (await jogosEspn(c, DateTime(2026, 11, 28), {'nba'})).dados;
      expect(dia28.map((j) => j.casa), containsAll(['New York Knicks', 'Indiana Pacers']));
      expect(pedidos, containsAll(['/apis/site/v2/sports/basketball/nba/scoreboard 20261127',
          '/apis/site/v2/sports/basketball/nba/scoreboard 20261128']));
      final dia27 = (await jogosEspn(c, DateTime(2026, 11, 27), {'nba'})).dados;
      expect(dia27, isEmpty, reason: 'em Lisboa já são do dia 28');
    });

    test('«INDIANA PACERS X PHILADELPHIA 76ERS» na Sport TV casa com o jogo da ESPN', () {
      final j = lerNbaEspn(nba, {'nba'}).firstWhere((j) => j.casa == 'Indiana Pacers');
      final t = casar([j], [
        Emissao(
            canal: 'sporttv2',
            inicio: DateTime.utc(2026, 11, 28, 0, 30),
            fim: DateTime.utc(2026, 11, 28, 3),
            titulo: 'INDIANA PACERS X PHILADELPHIA 76ERS',
            origem: 'sporttv',
            direto: true,
            modalidade: 'Basquetebol'),
      ]);
      expect(t.single.canal, 'sporttv2');
      expect(t.single.confianca, Confianca.confirmado);
    });
  });

  group('Liga Betclic (FPB)', () {
    test('«SC Braga x SL Benfica» de 5/12 às 18:00 (hora de Lisboa)', () {
      final js = lerFpb(fpb, {'lpb'});
      expect(js, hasLength(8));
      final j = js.singleWhere((j) => j.casa == 'SC Braga');
      expect(j.fora, 'SL Benfica');
      expect(j.inicio, DateTime.utc(2026, 12, 5, 18), reason: 'em dezembro Lisboa = UTC');
      expect(j.competicaoId, 'lpb');
      expect(j.desporto, Desporto.basquetebol);
      expect(j.id, 'fpb:414136');
      expect(js.where((j) => j.inicio.day == 12), hasLength(2));
      expect(lerFpb(fpb, {'nba'}), isEmpty);
    });

    test('casa com a DAZN quando a grelha o tem', () {
      final j = lerFpb(fpb, {'lpb'}).singleWhere((j) => j.casa == 'SC Braga');
      final t = casar([j], [
        Emissao(
            canal: 'dazn1',
            inicio: DateTime.utc(2026, 12, 5, 18),
            fim: DateTime.utc(2026, 12, 5, 20),
            titulo: 'SC Braga x SL Benfica (Direto)',
            origem: 'epg',
            direto: true),
      ]);
      expect(t.single.canal, 'dazn1');
    });

    test('jogosFpb: um pedido para os próximos jogos, filtrado pelo dia', () async {
      final pasta = Directory.systemTemp.createTempSync('fpb');
      addTearDown(() => pasta.deleteSync(recursive: true));
      var pedidos = 0;
      final c = ClienteDesporto(await ArmazemDesporto.abrir(pasta), agora: () => DateTime.utc(2026, 11, 27, 12),
          obter: (u, _) async {
        pedidos++;
        expect(u.host, 'www.fpb.pt');
        return fpb;
      });
      expect((await jogosFpb(c, DateTime(2026, 12, 5), {'lpb'})).dados, hasLength(6));
      expect((await jogosFpb(c, DateTime(2026, 12, 12), {'lpb'})).dados, hasLength(2));
      expect(pedidos, 1, reason: 'o segundo dia vem da cache');
      expect((await jogosFpb(c, DateTime(2026, 12, 5), {'nba'})).dados, isEmpty);
    });
  });
}
