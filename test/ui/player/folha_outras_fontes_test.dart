import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/ui/design/etiqueta.dart';
import 'package:player_iptv/ui/player/folha_outras_fontes.dart';

import '../ajuda_dpad.dart';

/// «Outras fontes» no player: as fontes do canal, a que toca marcada, com o comando.
void main() {
  const fontes = [
    (lista: 'Lista A', canal: 'Sport TV 1 HD', falhou: true),
    (lista: 'Lista B', canal: 'Sport TV 1 FHD', falhou: false),
    (lista: 'Lista C', canal: 'SPORT TV 1', falhou: false),
  ];

  Future<Completer<int?>> abrir(WidgetTester t, {int atual = 1}) async {
    ecraTvTeste(t);
    final escolhida = Completer<int?>();
    await t.pumpWidget(appTeste(Builder(
      builder: (c) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async => escolhida.complete(await mostrarOutrasFontes(c, fontes, atual: atual)),
            child: const Text('abrir'),
          ),
        ),
      ),
    )));
    await t.tap(find.text('abrir'));
    await t.pumpAndSettle();
    return escolhida;
  }

  testWidgets('mostra cada fonte (a lista e o nome do canal), a que toca e as que falharam', (t) async {
    await abrir(t);
    expect(find.text('Outras fontes'), findsOneWidget);
    for (final f in fontes) {
      expect(find.text(f.lista), findsOneWidget);
      expect(find.text(f.canal), findsOneWidget);
    }
    expect(find.widgetWithText(Etiqueta, 'A ver'), findsOneWidget);
    expect(find.widgetWithText(Etiqueta, 'Falhou'), findsOneWidget);
    expect(textosFocados(), contains('Lista B'), reason: 'o foco começa na fonte que está a tocar');
  });

  testWidgets('com o comando: BAIXO vai à fonte seguinte e OK escolhe-a', (t) async {
    final escolhida = await abrir(t);
    await teclaDpad(t, LogicalKeyboardKey.arrowDown);
    expect(textosFocados(), contains('Lista C'));
    await teclaDpad(t, LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(await escolhida.future, 2);
  });

  testWidgets('Voltar fecha sem escolher', (t) async {
    final escolhida = await abrir(t);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(await escolhida.future, isNull);
  });
}
