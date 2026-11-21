import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/ui/design/design.dart';
import 'package:player_iptv/ui/tema.dart';

/// Task 8: a pressão longa no CartaoModerno (toque longo, clique direito, OK mantido no comando);
/// um OK curto continua a abrir.
void main() {
  late int toques, longos;

  Future<void> montar(WidgetTester t) async {
    toques = 0;
    longos = 0;
    await t.pumpWidget(MaterialApp(
      theme: temaApp(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            height: 150,
            child: CartaoModerno(
              autofocus: true,
              onTap: () => toques++,
              onLongPress: () => longos++,
              child: const Text('Cartão'),
            ),
          ),
        ),
      ),
    ));
    await t.pump();
  }

  testWidgets('toque longo abre o menu; toque curto abre a lista', (t) async {
    await montar(t);
    await t.longPress(find.text('Cartão'));
    expect((toques, longos), (0, 1));
    await t.tap(find.text('Cartão'));
    expect((toques, longos), (1, 1));
  });

  testWidgets('clique direito do rato abre o menu', (t) async {
    await montar(t);
    await t.tap(find.text('Cartão'), buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
    await t.pump();
    expect((toques, longos), (0, 1));
  });

  for (final k in [LogicalKeyboardKey.select, LogicalKeyboardKey.enter]) {
    testWidgets('OK curto ($k) abre uma vez; mantido abre o menu (uma vez) e não abre a lista', (t) async {
      await montar(t);
      await t.sendKeyDownEvent(k);
      await t.pump(const Duration(milliseconds: 100));
      await t.sendKeyUpEvent(k);
      await t.pump();
      expect((toques, longos), (1, 0));

      await t.sendKeyDownEvent(k);
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 50));
        await t.sendKeyRepeatEvent(k);
      }
      await t.pump(const Duration(milliseconds: 100));
      expect((toques, longos), (1, 1), reason: 'o menu abre enquanto o OK está em baixo');
      await t.sendKeyUpEvent(k);
      await t.pump();
      expect((toques, longos), (1, 1), reason: 'soltar depois do menu não abre a lista');
    });
  }

  testWidgets('repetições de OK que chegam sem o OK ter começado no cartão não abrem a lista', (t) async {
    await montar(t);
    // ex.: OK numa opção do menu fechou-o, o foco voltou ao cartão e o OK continua em baixo
    for (var i = 0; i < 5; i++) {
      await t.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    }
    await t.sendKeyUpEvent(LogicalKeyboardKey.select);
    await t.pump(const Duration(seconds: 1));
    expect((toques, longos), (0, 0));
  });
}
