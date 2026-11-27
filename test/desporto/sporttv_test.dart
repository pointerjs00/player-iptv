import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/desporto/devalue.dart';
import 'package:player_iptv/desporto/fontes/sporttv.dart';

/// O guia oficial da Sport TV: a grelha vem na página, em `__NUXT_DATA__` (formato devalue).
void main() {
  final pagina = File('test/desporto/respostas/sporttv-guia.html').readAsStringSync();

  group('devalue', () {
    test('resolve as referências e os marcadores Reactive/Ref/Set/Map/Date', () {
      final raiz = [
        ['Reactive', 1],
        {'a': 2, 'b': 3, 'c': 5, 'd': 7},
        'texto',
        [4],
        42,
        ['Ref', 6],
        true,
        ['Date', '2026-11-27T20:00:00.000Z'],
      ];
      expect(lerDevalue(raiz), {
        'a': 'texto',
        'b': [42],
        'c': true,
        'd': DateTime.utc(2026, 11, 27, 20),
      });
    });

    test('os ciclos não rebentam', () {
      final raiz = [
        {'eu': 0},
      ];
      expect(() => lerDevalue(raiz), returnsNormally);
    });
  });

  group('guia', () {
    final es = lerGuiaSportTv(pagina);

    test('o jogo em direto, com o canal, a hora, a duração, a modalidade e a competição', () {
      final m = es.singleWhere((e) => e.titulo.contains('MARÍTIMO X CD NACIONAL') && !e.titulo.contains('ANTEVIS'));
      expect(m.canal, 'sporttv1');
      expect(m.inicio, DateTime.utc(2026, 11, 27, 20, 1));
      expect(m.fim, DateTime.utc(2026, 11, 27, 22, 33));
      expect(m.direto, isTrue);
      expect(m.modalidade, 'futebol');
      expect(m.evento, 'LIGA PORTUGAL BETCLIC - FUTEBOL');
      expect(m.origem, 'sporttv');
    });

    test('a antevisão é lida, mas o título diz que não é o jogo', () {
      final a = es.singleWhere((e) => e.titulo.contains('ANTEVIS'));
      expect(a.canal, 'sporttv1');
    });

    test('NBA em direto na Sport TV 1 e a repetição na Sport TV 2', () {
      final nba = es.where((e) => e.titulo.contains('INDIANA PACERS')).toList();
      expect(nba.map((e) => (e.canal, e.direto)), [('sporttv1', true), ('sporttv2', false)]);
      expect(nba.first.modalidade, 'basquetebol');
    });

    test('a Sport TV + (SPORT.TV +)', () {
      expect(es.singleWhere((e) => e.titulo.contains('FEIRENSE')).canal, 'sporttvmais');
    });

    test('página sem grelha → vazia', () {
      expect(lerGuiaSportTv(File('test/desporto/respostas/sporttv-sem-dados.html').readAsStringSync()), isEmpty);
      expect(lerGuiaSportTv('<script id="__NUXT_DATA__">[estragado</script>'), isEmpty);
    });
  });
}
