import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/ui/inicio/tela_inicio.dart';

import 'apoio_telemovel.dart';

/// O Início num telemóvel ao alto (360×800 e 412×915, letra a 1 e a 1,3, com a Roboto): os
/// filtros todos à vista, «Continuar a ver» legível e nada transborda.

const _longo = Canal(
  id: 'c1',
  nome: '|PT| SPORT TV 1 FHD (DIRETO)',
  grupo: '|PT| DESPORTO',
);

void main() {
  late Directory pasta;
  late Biblioteca bib;

  setUpAll(carregarRoboto);
  setUp(() async {
    pasta = Directory.systemTemp.createTempSync('inicio_telemovel');
    bib = await Biblioteca.abrir(pasta);
  });
  tearDown(() {
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {
      /* Windows */
    }
  });

  /// Android (não TV) e, no fim do corpo, o repor (antes das verificações do teste).
  void noAndroid(String nome, Future<void> Function(WidgetTester t, Size ecra) corpo) =>
      noTelemovel(nome, (t, ecra) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          await corpo(t, ecra);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });

  Future<void> abrir(WidgetTester t) async {
    await t.runAsync(() async {
      await bib.adicionar([
        Importada(
          contaDeLinha(
            'http://servidor-alfa.exemplo.invalid/lista.m3u',
          )!,
        ),
        Importada(contaDeLinha('http://bravo.exemplo.invalid/lista.m3u')!),
      ]);
      await bib.registarVisto(bib.listas.first.id, _longo);
    });
    await t.pumpWidget(appTelemovel(TelaInicio(biblioteca: bib)));
    for (var i = 0; i < 10; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await t.pump();
    }
    await t.pumpAndSettle();
  }

  noAndroid('filtros: os 6 à vista num Wrap, com «Inconclusivas»', (
    t,
    ecra,
  ) async {
    await abrir(t);
    for (final c in [
      'Todas',
      'Funcionam',
      'Inconclusivas',
      'Não funcionam',
      'Por verificar',
      'Favoritas',
    ]) {
      final chip = find.widgetWithText(ChoiceChip, c).hitTestable();
      expect(chip, findsOneWidget, reason: c);
      noEcra(t, chip, ecra, motivo: c);
      inteiro(t, find.descendant(of: chip, matching: find.text(c)));
      expect(
        find.ancestor(of: chip, matching: find.byType(Wrap)),
        findsOneWidget,
        reason: '$c num Wrap',
      );
    }
    expect(find.text('INC'), findsNothing);
    // filtrar continua a funcionar
    await t.tap(find.widgetWithText(ChoiceChip, 'Inconclusivas'));
    await t.pumpAndSettle();
    expect(find.text('Nenhuma lista com este filtro.'), findsOneWidget);
  });

  noTelemovel(
    '«Continuar a ver»: rótulo curto, o canal numa linha própria e só o ▶',
    (t, ecra) async {
      final sem = t.ensureSemantics();
      await abrir(t);
      final cartao = find.byKey(const Key('continuar-a-ver'));
      expect(cartao, findsOneWidget);
      final rotulo = find.descendant(
        of: cartao,
        matching: find.text('Continuar a ver'),
      );
      expect(rotulo, findsOneWidget);
      expect(
        find.descendant(of: cartao, matching: find.textContaining('CONTINUAR')),
        findsNothing,
      );
      final nome = find.descendant(
        of: cartao,
        matching: find.text(_longo.nome),
      );
      expect(nome, findsOneWidget);
      // inteiro, até 2 linhas, por baixo do rótulo e sem mais nada ao lado
      final p = t.renderObject<RenderParagraph>(
        find.descendant(of: nome, matching: find.byType(RichText)).first,
      );
      expect(p.didExceedMaxLines, isFalse, reason: 'o nome cabe em 2 linhas');
      expect(
        t.getRect(nome).top,
        greaterThanOrEqualTo(t.getRect(rotulo).bottom - .5),
      );
      final detalhe = find.descendant(
        of: cartao,
        matching: find.textContaining('|PT| DESPORTO'),
      );
      expect(detalhe, findsOneWidget);
      expect(
        t.getRect(detalhe).top,
        greaterThanOrEqualTo(t.getRect(nome).bottom - .5),
        reason: 'lista · grupo em baixo',
      );
      inteiro(t, detalhe);
      // o botão é só um ▶, lido como «Ver»
      expect(
        find.descendant(of: cartao, matching: find.text('Ver')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: cartao,
          matching: find.byIcon(Icons.play_arrow_rounded),
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Ver'), findsOneWidget);
      noEcra(t, cartao, ecra);
      sem.dispose();
    },
  );
}
