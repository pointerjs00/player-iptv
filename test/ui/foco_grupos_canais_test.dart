import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/ui/conteudo/tela_conteudo.dart';
import 'package:player_iptv/ui/design/ecra.dart';
import 'package:player_iptv/ui/realce_foco.dart';
import 'package:player_iptv/ui/tema.dart';

Widget _app(Widget w) =>
    MaterialApp(theme: temaApp(), builder: (_, c) => TemaConformeRealce(child: c!), home: w);

Future<void> _tecla(WidgetTester t, LogicalKeyboardKey k) async {
  await t.sendKeyEvent(k);
  await t.pumpAndSettle();
}

void main() {
  late Directory pasta;
  late Biblioteca bib;

  setUp(() async {
    pasta = Directory.systemTemp.createTempSync('foco-grupos');
    bib = await Biblioteca.abrir(pasta);
  });
  tearDown(() {
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  // Android TV: com os canais deslocados, DIREITA a partir dos grupos punha o foco num canal
  // meio escondido por baixo do nome do grupo (construído na cache da lista, fora da vista).
  testWidgets('DIREITA nos grupos vai sempre a um canal inteiro à vista', (t) async {
    EcraTv.nativo = true;
    addTearDown(() => EcraTv.nativo = false);
    t.view.physicalSize = const Size(960, 540);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
    await t.runAsync(() async {
      await bib.adicionar([Importada(contaDeLinha('http://x.com/l.m3u')!)]);
      await bib.guardarCanais(
          bib.listas.single.id,
          ConteudoLista(['Portugal', 'UK'], [
            for (var i = 0; i < 80; i++) Canal(id: '$i', nome: 'Canal $i', grupo: 'Portugal'),
            const Canal(id: 'b', nome: 'BBC', grupo: 'UK'),
          ]));
    });
    await t.runAsync(() async {
      await t.pumpWidget(_app(TelaConteudo(biblioteca: bib, lista: bib.listas.single)));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await t.pumpAndSettle();

    final vista = t.getRect(find.byKey(const Key('lista-canais')));
    // descer nos canais; depois, com a lista em vários deslocamentos, ESQUERDA e DIREITA
    await _tecla(t, LogicalKeyboardKey.arrowRight);
    for (var i = 0; i < 25; i++) {
      await _tecla(t, LogicalKeyboardKey.arrowDown);
    }
    final lista = t.widget<ListView>(find.byKey(const Key('lista-canais')));
    final base = lista.controller!.offset;
    for (var d = 0; d < 76; d += 4) {
      lista.controller!.jumpTo(base + d);
      await t.pumpAndSettle();
      await _tecla(t, LogicalKeyboardKey.arrowLeft);
      await _tecla(t, LogicalKeyboardKey.arrowRight);
      final r = FocusManager.instance.primaryFocus!.rect;
      expect(r.top, greaterThanOrEqualTo(vista.top - 0.5), reason: 'deslocado $d: canal cortado em cima');
      expect(r.bottom, lessThanOrEqualTo(vista.bottom + 0.5), reason: 'deslocado $d: canal cortado em baixo');
    }
  });
}
