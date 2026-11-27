import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/desporto/armazem_desporto.dart';
import 'package:player_iptv/desporto/catalogo.dart';
import 'package:player_iptv/desporto/cliente_desporto.dart';
import 'package:player_iptv/desporto/fontes/meo.dart';
import 'package:player_iptv/desporto/hora_lisboa.dart';

/// A grelha da MEO por canal e por dia (recortes das respostas de 27/11/2026) e a hora de Lisboa.
void main() {
  String resposta(String n) => File('test/desporto/respostas/$n').readAsStringSync();
  final sporttv1 = canalPorId('sporttv1')!, dazn2 = canalPorId('dazn2')!;

  group('hora de Lisboa', () {
    test('inverno: a hora de Lisboa é UTC', () {
      expect(lisboaParaUtc(DateTime.utc(2026, 1, 15, 20)), DateTime.utc(2026, 1, 15, 20));
      expect(lisboaParaUtc(DateTime.utc(2026, 11, 27, 20, 1)), DateTime.utc(2026, 11, 27, 20, 1));
    });
    test('verão: UTC + 1', () {
      expect(lisboaParaUtc(DateTime.utc(2026, 7, 15, 20)), DateTime.utc(2026, 7, 15, 19));
    });
    test('as mudanças no último domingo de março e de outubro (01:00 UTC)', () {
      // 2026: 29 de março e 25 de outubro
      expect(lisboaParaUtc(DateTime.utc(2026, 3, 29, 0, 30)), DateTime.utc(2026, 3, 29, 0, 30));
      expect(lisboaParaUtc(DateTime.utc(2026, 3, 29, 3)), DateTime.utc(2026, 3, 29, 2));
      expect(lisboaParaUtc(DateTime.utc(2026, 10, 25, 3)), DateTime.utc(2026, 10, 25, 3));
      expect(lisboaParaUtc(DateTime.utc(2026, 10, 24, 20)), DateTime.utc(2026, 10, 24, 19));
    });
  });

  group('grelha', () {
    test('o jogo em direto, sem o enchimento nem a antevisão', () {
      final es = lerGrelhaMeo(resposta('meo-SPT1HD-2026-11-27.json'), sporttv1);
      expect(es.map((e) => e.titulo), [
        'Feyenoord x FC Porto - Liga dos Campeões',
        'Marítimo x CD Nacional - Liga Portugal Betclic (Direto)',
      ]);
      final m = es.last;
      expect(m.canal, 'sporttv1');
      expect(m.inicio, DateTime.utc(2026, 11, 27, 20, 1));
      expect(m.fim, DateTime.utc(2026, 11, 27, 22, 33));
      expect(m.direto, isTrue);
      expect(m.origem, 'meo');
      expect(es.first.direto, isNull, reason: 'sem «(Direto)» a MEO não diz');
    });

    test('a repetição da DAZN fica como emissão (o casador decide pela hora); o nome do canal não', () {
      final es = lerGrelhaMeo(resposta('meo-DAZN2-2026-11-27.json'), dazn2);
      expect(es.map((e) => e.titulo), contains('Ajax x FC Thun - UEFA Conference League'));
      expect(es.map((e) => e.titulo), isNot(contains('DAZN 2')));
      expect(es, hasLength(3));
    });

    test('resposta com erro ou estragada → vazia', () {
      expect(lerGrelhaMeo(resposta('meo-erro.json'), sporttv1), isEmpty);
      expect(lerGrelhaMeo('<html>', sporttv1), isEmpty);
    });
  });

  test('pede o canal e o dia certos, com a cache', () async {
    final pasta = Directory.systemTemp.createTempSync('meo');
    addTearDown(() => pasta.deleteSync(recursive: true));
    final pedidos = <Uri>[];
    final c = ClienteDesporto(await ArmazemDesporto.abrir(pasta), agora: () => DateTime.utc(2026, 11, 27, 12),
        obter: (u, _) async {
      pedidos.add(u);
      return resposta('meo-SPT1HD-2026-11-27.json');
    });
    final r = await grelhaMeo(c, sporttv1, DateTime(2026, 11, 27));
    expect(r.dados, hasLength(2));
    expect(pedidos.single.host, 'meogouser.apps.meo.pt');
    expect(pedidos.single.queryParameters, {'callLetter': 'SPT1HD', 'date': '2026-11-27', 'userAgent': 'IPTV_OFR_GTV'});
    await grelhaMeo(c, sporttv1, DateTime(2026, 11, 27));
    expect(pedidos, hasLength(1));
  });
}
