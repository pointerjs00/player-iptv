import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/ui/player/taxa_ecra.dart';

void main() {
  const tv = [24.0, 25.0, 30.0, 50.0, 60.0];
  group('escolherTaxa', () {
    test('50 fps (TV portuguesa) -> 50 Hz', () => expect(escolherTaxa(50, tv), 50));
    test('25 fps -> 50 Hz (o múltiplo mais alto até 60)', () => expect(escolherTaxa(25, tv), 50));
    test('30 fps -> 60 Hz', () => expect(escolherTaxa(30, tv), 60));
    test('60 fps -> 60 Hz', () => expect(escolherTaxa(60, tv), 60));
    test('29.97 prefere 59.94 a 60 se existir', () {
      expect(escolherTaxa(29.97, [50, 59.94, 60]), 59.94);
      expect(escolherTaxa(29.97, [50, 60]), 60);
    });
    test('24 fps -> 24 Hz', () => expect(escolherTaxa(24, tv), 24));
    test('25 fps com o 50 indisponível -> 25 Hz', () => expect(escolherTaxa(25, [25, 60]), 25));
    test('nenhum modo compatível -> não mexe', () => expect(escolherTaxa(50, [60]), isNull));
    test('fps desconhecido -> não mexe', () {
      expect(escolherTaxa(0, tv), isNull);
      expect(escolherTaxa(double.nan, tv), isNull);
    });
    test('só modos acima de 60: o mais baixo compatível', () => expect(escolherTaxa(25, [100, 120]), 100));
  });

  group('TaxaEcra', () {
    late List<(String, Object?)> chamadas;
    late Map<String, Object?> taxas;
    late TaxaEcra t;
    setUp(() {
      chamadas = [];
      taxas = {'atual': 60.0, 'suportadas': tv};
      t = TaxaEcra(invocar: (m, [a]) async {
        chamadas.add((m, a));
        return m == 'taxas' ? taxas : true;
      });
    });

    test('pede o modo certo para o canal', () async {
      expect(await t.ajustarPara(50), 50);
      expect(chamadas.last.$1, 'pedir');
      expect(chamadas.last.$2, {'hz': 50.0});
    });

    test('já está no modo certo: não pede (não pisca o ecrã)', () async {
      taxas = {'atual': 50.0, 'suportadas': tv};
      expect(await t.ajustarPara(25), isNull);
      expect(chamadas.map((c) => c.$1), ['taxas']);
    });

    test('repor só se tiver pedido algo', () async {
      await t.repor();
      expect(chamadas, isEmpty);
      await t.ajustarPara(50);
      await t.repor();
      expect(chamadas.last.$1, 'repor');
    });

    test('um erro do canal nativo não rebenta o player', () async {
      final f = TaxaEcra(invocar: (m, [a]) async => throw Exception('sem canal'));
      expect(await f.ajustarPara(50), isNull);
      await f.repor();
    });
  });

  group('TaxaEcra: saídas e corridas (M1)', () {
    test('Voltar a meio do pedido: o modo pedido depois de sair é reposto', () async {
      final chamadas = <String>[];
      final pedir = Completer<Object?>();
      final t = TaxaEcra(invocar: (m, [a]) {
        chamadas.add(m);
        if (m == 'taxas') return Future.value({'atual': 60.0, 'suportadas': [50.0, 60.0]});
        if (m == 'pedir') return pedir.future;
        return Future.value(true);
      });
      final f = t.ajustarPara(50);
      await Future<void>.delayed(Duration.zero);
      expect(chamadas, ['taxas', 'pedir']);
      await t.fechar(); // dispose do player enquanto o "pedir" ainda não respondeu
      pedir.complete(true);
      await f;
      expect(chamadas.last, 'repor', reason: 'nunca fica preso no modo pedido');
    });

    test('fechado antes de responder às taxas: não pede nada', () async {
      final chamadas = <String>[];
      final taxas = Completer<Object?>();
      final t = TaxaEcra(invocar: (m, [a]) {
        chamadas.add(m);
        return m == 'taxas' ? taxas.future : Future.value(true);
      });
      final f = t.ajustarPara(50);
      await t.fechar();
      taxas.complete({'atual': 60.0, 'suportadas': [50.0, 60.0]});
      expect(await f, isNull);
      expect(chamadas, ['taxas']);
    });

    test('repor é idempotente; depois de fechar não volta a pedir', () async {
      final chamadas = <String>[];
      final t = TaxaEcra(invocar: (m, [a]) async {
        chamadas.add(m);
        return m == 'taxas' ? {'atual': 60.0, 'suportadas': [50.0, 60.0]} : true;
      });
      await t.ajustarPara(50);
      await t.repor();
      await t.repor();
      expect(chamadas.where((c) => c == 'repor').length, 1);
      // a app voltou ao primeiro plano: pode pedir de novo
      await t.ajustarPara(50);
      expect(chamadas.where((c) => c == 'pedir').length, 2);
      await t.fechar();
      await t.fechar();
      expect(chamadas.where((c) => c == 'repor').length, 2);
      expect(await t.ajustarPara(50), isNull);
      expect(chamadas.where((c) => c == 'pedir').length, 2);
    });

    test('hzAtual: os Hz do ecrã segundo o sistema', () async {
      final t = TaxaEcra(invocar: (m, [a]) async => {'atual': 59.94, 'suportadas': [59.94]});
      expect(await t.hzAtual(), 59.94);
      final f = TaxaEcra(invocar: (m, [a]) async => throw Exception('x'));
      expect(await f.hzAtual(), isNull);
    });
  });
}
