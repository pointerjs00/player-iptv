import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/ui/inicio/tela_inicio.dart';
import 'package:player_iptv/ui/principal/tela_principal.dart';

import 'ajuda_dpad.dart';

/// Os filtros por estado do Início, só com o comando.
void main() {
  late Directory pasta;
  late Biblioteca bib;

  setUp(() async {
    pasta = Directory.systemTemp.createTempSync('inicio-filtros');
    bib = await Biblioteca.abrir(pasta);
  });
  tearDown(() {
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  Future<void> abrir(WidgetTester t, {bool casca = true}) async {
    await t.runAsync(() => bib.adicionar([
          for (var i = 0; i < 4; i++) Importada(contaDeLinha('http://h$i.com/l$i.m3u')!),
        ]));
    final inicio = TelaInicio(biblioteca: bib);
    await t.pumpWidget(appTeste(casca
        ? TelaPrincipal(verTv: inicio, gestor: const SizedBox(), definicoes: const SizedBox(), sair: () {})
        : inicio));
    await t.pump();
    await t.pump();
  }

  /// Do primeiro cartão, CIMA até à pesquisa.
  Future<void> irParaPesquisa(WidgetTester t) async {
    bool naPesquisa() => t.widget<EditableText>(find.byType(EditableText)).focusNode.hasPrimaryFocus;
    final caminho = <String>[];
    for (var i = 0; i < 4 && !naPesquisa(); i++) {
      await teclaDpad(t, LogicalKeyboardKey.arrowUp);
      caminho.add('${FocusManager.instance.primaryFocus} ${textosFocados()}');
    }
    expect(naPesquisa(), isTrue, reason: 'CIMA até à pesquisa: $caminho');
  }

  /// Se o foco está no filtro com este texto (e não num cartão que diga o mesmo).
  bool noFiltro(WidgetTester t, String texto) {
    final chip = t.element(find.widgetWithText(ChoiceChip, texto));
    var dentro = false;
    FocusManager.instance.primaryFocus?.context?.visitAncestorElements((a) => !(dentro = a == chip));
    return dentro;
  }

  for (final (nome, largura, altura) in [
    ('TV 960×540', 960.0, 540.0),
    ('Windows 1280×800', 1280.0, 800.0),
    ('telemóvel 400×800', 400.0, 800.0),
  ]) {
    for (final casca in [true, false]) {
      testWidgets('o filtro Por verificar recebe o foco e escolhe-se com OK ($nome${casca ? ', na casca' : ''})',
          (t) async {
        ecraTvTeste(t, largura: largura, altura: altura);
        await abrir(t, casca: casca);
        await irParaPesquisa(t);
        final caminho = <String>[];
        // → de filtro em filtro: com a fila partida em duas, do fim da 1.ª linha → não ia a lado
        // nenhum e ↓ saltava para os cartões
        // (→ não mexe: no fim da linha, ou no telemóvel com a pesquisa sozinha numa linha, desce-se)
        for (var i = 0; i < 8 && !noFiltro(t, 'Por verificar'); i++) {
          final antes = FocusManager.instance.primaryFocus;
          await teclaDpad(t, LogicalKeyboardKey.arrowRight);
          if (FocusManager.instance.primaryFocus == antes) await teclaDpad(t, LogicalKeyboardKey.arrowDown);
          caminho.add(textosFocados());
        }
        expect(noFiltro(t, 'Por verificar'), isTrue, reason: '→: $caminho');
        await teclaDpad(t, LogicalKeyboardKey.select);
        final chip = t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Por verificar'));
        expect(chip.selected, isTrue);
        // todas as listas estão por verificar: continuam todas
        expect(find.text('Nenhuma lista com este filtro.'), findsNothing);
      });
    }
  }
}
