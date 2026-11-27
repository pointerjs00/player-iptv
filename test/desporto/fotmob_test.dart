import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/desporto/armazem_desporto.dart';
import 'package:player_iptv/desporto/catalogo.dart';
import 'package:player_iptv/desporto/cliente_desporto.dart';
import 'package:player_iptv/desporto/fontes/fotmob.dart';
import 'package:player_iptv/desporto/modelo.dart';

/// Os jogos do dia e o guia de TV de Portugal do FotMob (recortes das respostas de 27/11/2026).
void main() {
  final jogos = File('test/desporto/respostas/fotmob-matches-20261127.json').readAsStringSync();
  final guia = File('test/desporto/respostas/fotmob-tvguide-pt.json').readAsStringSync();
  final seguidas = {for (final c in catalogoCompeticoes) c.id};

  group('jogos do dia', () {
    final js = lerJogosFotmob(jogos, seguidas);
    Jogo jogo(String casa) => js.singleWhere((j) => j.casa == casa);

    test('filtra pelo primaryId: a Pro League belga (id 937988) entra; a Botola Pro não', () {
      expect(jogo('OH Leuven').competicaoId, 'pro-league');
      expect(js.where((j) => j.casa == 'US Amal Tiznit'), isEmpty);
      expect(js.where((j) => j.casa == 'Arsenal (W)'), isEmpty, reason: 'competição não seguida');
    });

    test('reconhece pelo nome e país as competições sem id confirmado', () {
      expect(jogo('Al Hilal').competicaoId, 'taca-rei');
      expect(jogo('Al Hilal').estado, EstadoJogo.terminado);
      expect(jogo('Al Hilal').resultado, '3–0');
    });

    test('hora em UTC, nome curto, emblemas e estado', () {
      final j = jogo('Nottingham Forest');
      expect(j.id, 'fotmob:5795533');
      expect(j.inicio, DateTime.utc(2026, 11, 27, 20));
      expect(j.casaCurto, 'Nottm Forest');
      expect(j.estado, EstadoJogo.agendado);
      expect(j.resultado, isNull);
      expect(j.emblemaCasa, contains('10203'));
      expect(j.ronda, '12');
    });

    test('ao vivo: o resultado e o minuto sem os caracteres invisíveis', () {
      final j = jogo('Marítimo');
      expect(j.estado, EstadoJogo.aoVivo);
      expect(j.resultado, '2–1');
      expect(j.minuto, "67'");
    });

    test('só as competições pedidas', () {
      expect(lerJogosFotmob(jogos, {'liga-portugal'}).map((j) => j.casa), ['Marítimo', 'Moreirense']);
    });

    test('resposta estragada → lista vazia', () {
      expect(lerJogosFotmob('<html>', seguidas), isEmpty);
      expect(lerJogosFotmob('{"leagues": 3}', seguidas), isEmpty);
    });
  });

  group('guia de TV', () {
    final g = lerGuiaFotmob(guia);

    test('Marítimo–Nacional dá na Sport TV 1, ligado pelo id do jogo', () {
      final e = g.where((x) => x.$1 == 'fotmob:5887685').toList();
      expect(e, hasLength(1));
      expect(e.single.$2.canal, 'sporttv1');
      expect(e.single.$2.inicio, DateTime.utc(2026, 11, 27, 20, 15));
      expect(e.single.$2.origem, 'fotmob');
    });

    test('só os canais portugueses do catálogo («DAZN» e «Fanatiz» ficam de fora)', () {
      expect(g.where((x) => x.$1 == 'fotmob:5795533').map((x) => x.$2.canal), ['dazn1']);
      expect(g.where((x) => x.$1 == 'fotmob:5803002').map((x) => x.$2.canal), ['sporttv3']);
    });

    test('«Canal a confirmar» não é um canal', () {
      expect(g.where((x) => x.$1 == 'fotmob:5887690'), isEmpty);
      expect(g.where((x) => x.$1 == 'fotmob:5887691'), hasLength(1));
    });
  });

  test('pede o dia de Lisboa com a cache; o guia num pedido', () async {
    final pasta = Directory.systemTemp.createTempSync('fotmob');
    addTearDown(() => pasta.deleteSync(recursive: true));
    final pedidos = <Uri>[];
    final c = ClienteDesporto(await ArmazemDesporto.abrir(pasta), agora: () => DateTime.utc(2026, 11, 27, 12),
        obter: (u, _) async {
      pedidos.add(u);
      return u.path.contains('tvguide') ? guia : jogos;
    });
    final r = await jogosFotmob(c, DateTime(2026, 11, 27), seguidas);
    expect(r.dados, isNotEmpty);
    expect(pedidos.single.queryParameters['date'], '20261127');
    expect(pedidos.single.queryParameters['timezone'], 'Europe/Lisbon');
    final t = await guiaTvFotmob(c);
    expect(t.dados, isNotEmpty);
    expect(pedidos.last.queryParameters['country'], 'pt');
    await jogosFotmob(c, DateTime(2026, 11, 27), seguidas);
    expect(pedidos, hasLength(2), reason: 'a 2.ª vez vem da cache');
  });
}
