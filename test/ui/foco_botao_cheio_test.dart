import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/ui/design/design.dart';
import 'package:player_iptv/ui/realce_foco.dart';
import 'package:player_iptv/ui/tema.dart';

/// F1: na TV o foco num botão cheio (gradiente) tem de se ver: um anel claro à volta e brilho
/// por fora. Com o toque/rato, nada muda (I1).

final _chave = GlobalKey();

Future<ui.Image> _pintar(WidgetTester t, {required bool comando}) async {
  FocusManager.instance.highlightStrategy =
      comando ? FocusHighlightStrategy.alwaysTraditional : FocusHighlightStrategy.alwaysTouch;
  addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
  t.view.physicalSize = const Size(400, 200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: temaApp(),
    builder: (_, c) => TemaConformeRealce(child: c!),
    home: Scaffold(
      backgroundColor: Tokens.fundo,
      body: Center(
        child: RepaintBoundary(
          key: _chave,
          child: Container(
            color: Tokens.fundo,
            padding: const EdgeInsets.all(30),
            child: SizedBox(
              width: 200,
              height: 50,
              child: FilledButton(autofocus: true, onPressed: () {}, child: const SizedBox()),
            ),
          ),
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
  final rb = _chave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await t.runAsync(() => rb.toImage()))!;
}

Future<Color> _pixel(WidgetTester t, ui.Image im, int x, int y) async {
  final bytes = (await t.runAsync(() => im.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
  final i = (y * im.width + x) * 4;
  return Color.fromARGB(bytes.getUint8(i + 3), bytes.getUint8(i), bytes.getUint8(i + 1), bytes.getUint8(i + 2));
}

double _luz(Color c) => (c.r + c.g + c.b) / 3;

void main() {
  testWidgets('com o comando: anel claro na borda do botão cheio e brilho por fora', (t) async {
    final im = await _pintar(t, comando: true);
    // o botão vai de (30,30) a (230,80): a meio da borda esquerda, 1 px para dentro
    final borda = await _pixel(t, im, 31, 55);
    expect(_luz(borda), greaterThan(.85), reason: 'anel claro: $borda');
    // por fora (4 px à esquerda) há brilho: mais claro que o fundo
    final fora = await _pixel(t, im, 26, 55);
    final fundo = await _pixel(t, im, 2, 2);
    expect(_luz(fora), greaterThan(_luz(fundo) + .03), reason: 'brilho: $fora vs fundo $fundo');
    await t.sendKeyEvent(LogicalKeyboardKey.tab); // nada de estado pendurado
  });

  testWidgets('no toque/rato (I1): sem anel nem brilho', (t) async {
    final im = await _pintar(t, comando: false);
    final borda = await _pixel(t, im, 31, 55);
    expect(_luz(borda), lessThan(.8), reason: 'sem anel: $borda');
    final fora = await _pixel(t, im, 26, 55);
    final fundo = await _pixel(t, im, 2, 2);
    expect((_luz(fora) - _luz(fundo)).abs(), lessThan(.03), reason: 'sem brilho: $fora vs $fundo');
  });
}
