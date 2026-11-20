import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/ui/inicio/tela_inicio.dart';

import 'ajuda_dpad.dart';

/// As listas favoritas do Início: menu, estrela no cartão e filtro «Favoritas».
void main() {
  late Directory pasta;
  late Biblioteca bib;

  setUp(() async {
    pasta = Directory.systemTemp.createTempSync('inicio-favoritas');
    bib = await Biblioteca.abrir(pasta);
  });
  tearDown(() {
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  Future<void> abrir(WidgetTester t) async {
    await t.runAsync(() => bib.adicionar([
          for (var i = 0; i < 3; i++) Importada(contaDeLinha('http://h$i.com/l$i.m3u')!),
        ]));
    await t.pumpWidget(appTeste(TelaInicio(biblioteca: bib)));
    await t.pump();
    await t.pump();
  }

  Future<void> menuDoPrimeiro(WidgetTester t) async {
    await t.longPress(find.text(bib.listas.first.nomeMostrado));
    await t.pumpAndSettle();
  }

  testWidgets('«Pôr nas favoritas» mostra a estrela e o chip Favoritas filtra; «Tirar» desfaz', (t) async {
    ecraTvTeste(t);
    await abrir(t);
    expect(find.byKey(const Key('lista-favorita')), findsNothing);
    await menuDoPrimeiro(t);
    expect(find.text('Tirar das favoritas'), findsNothing);
    await t.tap(find.text('Pôr nas favoritas'));
    await t.pumpAndSettle();
    expect(bib.listas.first.favorita, isTrue);
    expect(find.byKey(const Key('lista-favorita')), findsOneWidget);

    await t.ensureVisible(find.widgetWithText(ChoiceChip, 'Favoritas'));
    await t.tap(find.widgetWithText(ChoiceChip, 'Favoritas'));
    await t.pumpAndSettle();
    expect(find.byType(ChoiceChip), findsWidgets);
    expect(find.text(bib.listas.first.nomeMostrado), findsOneWidget);
    expect(find.text(bib.listas.last.nomeMostrado), findsNothing);

    await menuDoPrimeiro(t);
    await t.tap(find.text('Tirar das favoritas'));
    await t.pumpAndSettle();
    expect(bib.listas.first.favorita, isFalse);
    expect(find.byKey(const Key('lista-favorita')), findsNothing);
    expect(find.text('Nenhuma lista com este filtro.'), findsOneWidget);
  });

  /// Com o filtro «Favoritas» ligado e [favoritas] listas favoritas (as primeiras), tira a primeira.
  Future<void> tirarDaPrimeira(WidgetTester t, int favoritas) async {
    ecraTvTeste(t);
    await abrir(t);
    for (final l in bib.listas.take(favoritas)) {
      await t.runAsync(() => bib.alternarFavorita(l.id));
    }
    await t.pump();
    await t.ensureVisible(find.widgetWithText(ChoiceChip, 'Favoritas'));
    await t.tap(find.widgetWithText(ChoiceChip, 'Favoritas'));
    await t.pumpAndSettle();
    await menuDoPrimeiro(t);
    await t.tap(find.text('Tirar das favoritas'));
    await t.pump();
    // a gravação do ficheiro acontece em tempo real
    for (var k = 0; k < 20; k++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump();
    }
    await t.pumpAndSettle();
  }

  testWidgets('«Tirar das favoritas» sob o filtro: o foco passa ao cartão que fica no lugar', (t) async {
    await tirarDaPrimeira(t, 2);
    expect(bib.listas.first.favorita, isFalse);
    expect(textosFocados(), contains(bib.listas[1].nomeMostrado));
  });

  testWidgets('«Tirar das favoritas» sob o filtro com a vista vazia: o foco vai ao chip «Favoritas»', (t) async {
    await tirarDaPrimeira(t, 1);
    expect(find.text('Nenhuma lista com este filtro.'), findsOneWidget);
    expect(textosFocados(), 'Favoritas');
  });

  testWidgets('o D-pad chega ao chip «Favoritas»', (t) async {
    ecraTvTeste(t);
    await abrir(t);
    for (var i = 0; i < 4; i++) {
      await teclaDpad(t, LogicalKeyboardKey.arrowUp);
    }
    final caminho = <String>[];
    bool nele() {
      final chip = t.element(find.widgetWithText(ChoiceChip, 'Favoritas'));
      var dentro = false;
      FocusManager.instance.primaryFocus?.context?.visitAncestorElements((a) => !(dentro = a == chip));
      return dentro;
    }

    for (var i = 0; i < 10 && !nele(); i++) {
      await teclaDpad(t, LogicalKeyboardKey.arrowRight);
      caminho.add(textosFocados());
    }
    expect(nele(), isTrue, reason: '→: $caminho');
    await teclaDpad(t, LogicalKeyboardKey.select);
    expect(t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Favoritas')).selected, isTrue);
  });
}
