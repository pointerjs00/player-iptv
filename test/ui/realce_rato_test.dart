import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/ui/realce_foco.dart';

void main() {
  testWidgets('no computador, um clique do rato esconde o realce do foco e uma tecla volta a mostrá-lo', (t) async {
    final vigia = RealceConformeEntrada()..instalar();
    addTearDown(() {
      vigia.desinstalar();
      FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
    });
    final foco = FocusNode();
    addTearDown(foco.dispose);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          ElevatedButton(focusNode: foco, autofocus: true, onPressed: () {}, child: const Text('A')),
          ElevatedButton(onPressed: () {}, child: const Text('B')),
        ]),
      ),
    ));
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    expect(FocusManager.instance.highlightMode, FocusHighlightMode.traditional);

    // clique com o rato noutro botão: o foco não muda, mas o realce deixa de se ver
    await t.tap(find.text('B'), kind: PointerDeviceKind.mouse);
    await t.pump();
    expect(FocusManager.instance.highlightMode, FocusHighlightMode.touch);

    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.pump();
    expect(FocusManager.instance.highlightMode, FocusHighlightMode.traditional);
  });

  testWidgets('no computador a app arranca sem realce (o cartão com foco automático não brilha) até uma tecla',
      (t) async {
    addTearDown(() async {
      await configurarRealceFoco(eTv: () async => false, computador: false);
      FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
    });
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional; // como o Windows ao abrir
    await configurarRealceFoco(eTv: () async => false, computador: true);
    await t.pumpWidget(MaterialApp(
        home: Scaffold(body: ElevatedButton(autofocus: true, onPressed: () {}, child: const Text('Continuar')))));
    await t.pump();
    expect(FocusManager.instance.highlightMode, FocusHighlightMode.touch);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    expect(FocusManager.instance.highlightMode, FocusHighlightMode.traditional);
  });

  testWidgets('configurarRealceFoco: no computador instala o vigia uma só vez e tira-o quando não se aplica',
      (t) async {
    addTearDown(() async {
      await configurarRealceFoco(eTv: () async => false, computador: false);
      FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
    });
    await t.pumpWidget(MaterialApp(home: Scaffold(body: ElevatedButton(onPressed: () {}, child: const Text('B')))));
    await configurarRealceFoco(eTv: () async => false, computador: true);
    await configurarRealceFoco(eTv: () async => false, computador: true);
    await t.tap(find.text('B'), kind: PointerDeviceKind.mouse);
    expect(FocusManager.instance.highlightStrategy, FocusHighlightStrategy.alwaysTouch);

    // sem computador (ou na TV), o rato já não mexe no modo
    await configurarRealceFoco(eTv: () async => false, computador: false);
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
    await t.tap(find.text('B'), kind: PointerDeviceKind.mouse);
    expect(FocusManager.instance.highlightStrategy, FocusHighlightStrategy.automatic);
  });
}
