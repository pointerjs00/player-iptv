import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/ui/inicio/cartao_lista.dart';
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

  Future<void> abrir(WidgetTester t, {Canal canal = _longo, bool comCache = false}) async {
    await t.runAsync(() async {
      await bib.adicionar([
        Importada(
          contaDeLinha(
            'http://servidor-alfa.exemplo.invalid/lista.m3u',
          )!,
        ),
        Importada(contaDeLinha('http://bravo.exemplo.invalid/lista.m3u')!),
      ]);
      if (comCache) {
        await bib.guardarCanais(
          bib.listas.first.id,
          ConteudoLista([canal.grupo], [Canal(id: 'x', nome: 'Antes', grupo: canal.grupo), canal]),
        );
      }
      await bib.registarVisto(bib.listas.first.id, canal);
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

  noAndroid('filtros: os 6 numa só fila que desliza, inteiros; «Ordenar» é um botão ao lado da pesquisa', (
    t,
    ecra,
  ) async {
    await abrir(t);
    final fila = find.byKey(const Key('fila-filtros'));
    expect(fila, findsOneWidget);
    double? linha;
    for (final c in [
      'Todas',
      'Funcionam',
      'Inconclusivas',
      'Não funcionam',
      'Por verificar',
      'Favoritas',
    ]) {
      final chip = find.widgetWithText(ChoiceChip, c);
      expect(find.descendant(of: fila, matching: chip), findsOneWidget, reason: '$c na fila');
      await t.ensureVisible(chip);
      await t.pumpAndSettle();
      noEcra(t, chip.hitTestable(), ecra, motivo: c);
      inteiro(t, find.descendant(of: chip, matching: find.text(c)));
      final y = t.getCenter(chip).dy;
      linha ??= y;
      expect(y, moreOrLessEquals(linha, epsilon: 1), reason: '$c na mesma linha');
      alvo48(t, find.descendant(of: chip, matching: find.byType(RawChip)), motivo: c);
    }
    final ordenar = find.byKey(const Key('ordenar-listas'));
    expect(t.getCenter(ordenar).dy, moreOrLessEquals(t.getCenter(find.byType(TextField)).dy, epsilon: 2),
        reason: 'ao lado da pesquisa');
    alvo48(t, ordenar);
    expect(find.text('INC'), findsNothing);
    // filtrar continua a funcionar
    await t.ensureVisible(find.widgetWithText(ChoiceChip, 'Inconclusivas'));
    await t.pumpAndSettle();
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

  noAndroid('nome com 60 caracteres: 2 linhas com reticências, sem overflow e o ▶ à vista', (t, ecra) async {
    final canal = Canal(
      id: 'c2',
      nome: '|PT| SPORT TV 1 FHD ALTERNATIVO COM UM NOME MESMO MUITO COMPRIDO (DIRETO)',
      grupo: '|PT| DESPORTO',
    );
    expect(canal.nome.length, greaterThanOrEqualTo(60));
    await abrir(t, canal: canal);
    final cartao = find.byKey(const Key('continuar-a-ver'));
    final nome = find.descendant(of: cartao, matching: find.text(canal.nome));
    final p = t.renderObject<RenderParagraph>(find.descendant(of: nome, matching: find.byType(RichText)).first);
    expect(p.didExceedMaxLines, isTrue, reason: 'cortado em 2 linhas, com reticências');
    expect(p.maxLines, 2);
    expect(p.overflow, TextOverflow.ellipsis);
    final seta = find.descendant(of: cartao, matching: find.byIcon(Icons.play_arrow_rounded));
    expect(seta.hitTestable(), findsOneWidget);
    noEcra(t, seta, ecra);
    noEcra(t, cartao, ecra);
  });

  noAndroid('com o número do canal: «lista · Canal n · grupo» sem overflow', (t, ecra) async {
    await abrir(t, comCache: true);
    final cartao = find.byKey(const Key('continuar-a-ver'));
    final detalhe = find.descendant(of: cartao, matching: find.textContaining('Canal 2'));
    expect(detalhe, findsOneWidget);
    final texto = t.widget<Text>(detalhe).data!;
    expect(texto, matches(r'^.+ · Canal 2 · \|PT\| DESPORTO$'));
    inteiro(t, detalhe);
    noEcra(t, detalhe, ecra);
  });
  noAndroid('cartão da lista: um ⋮ de 48 dp, «Opções da lista», abre o mesmo menu', (t, ecra) async {
    await abrir(t);
    final cartao = find.byType(CartaoLista).first;
    final mais = find.descendant(of: cartao, matching: find.widgetWithIcon(IconButton, Icons.more_vert));
    expect(mais.hitTestable(), findsOneWidget);
    expect(t.widget<IconButton>(mais).tooltip, 'Opções da lista');
    alvo48(t, mais);
    noEcra(t, mais, ecra);
    expect(find.byType(Dialog), findsNothing);
    await t.tap(mais);
    await t.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget, reason: 'o ⋮ abre o menu da lista');
    expect(find.descendant(of: find.byType(Dialog), matching: find.byType(ListTile)), findsAtLeastNWidgets(4),
        reason: 'as ações da lista (sem Gestor nem verificação neste ecrã: 4)');
  });

  testWidgets('cartão da lista: sem ⋮ num ecrã largo (Windows e TV ficam iguais)', (t) async {
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await abrir(t);
    expect(find.byType(CartaoLista), findsWidgets);
    expect(find.descendant(of: find.byType(CartaoLista), matching: find.byIcon(Icons.more_vert)), findsNothing);
  });
}
