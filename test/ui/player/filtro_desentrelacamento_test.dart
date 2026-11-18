import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/ui/player/filtro_desentrelacamento.dart';

void main() {
  test('o shader do Flutter compila e carrega (shaders/desentrelacar.frag)', () async {
    final p = await FiltroDesentrelacamento.programa();
    expect(p, isA<ui.FragmentProgram>());
  });

  testWidgets('sem o shader do Flutter (Skia): a textura fica sozinha, nunca parte o vídeo', (t) async {
    final p = await t.runAsync(FiltroDesentrelacamento.programa);
    const textura = SizedBox(key: ValueKey('textura'), width: 10, height: 10);
    await t.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: TexturaDesentrelacada(programa: p, colunas: 1920, linhas: 1080, suportado: false, child: textura),
    ));
    expect(find.byKey(const ValueKey('textura')), findsOneWidget);
    expect(find.byType(ImageFiltered), findsNothing);
  });

  testWidgets('sem o programa (não carregou): a textura fica sozinha', (t) async {
    const textura = SizedBox(key: ValueKey('textura'), width: 10, height: 10);
    await t.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: TexturaDesentrelacada(programa: null, colunas: 1920, linhas: 1080, suportado: true, child: textura),
    ));
    expect(find.byType(ImageFiltered), findsNothing);
    expect(find.byKey(const ValueKey('textura')), findsOneWidget);
  });

  testWidgets('sem o tamanho do vídeo: a textura fica sozinha', (t) async {
    final p = await t.runAsync(FiltroDesentrelacamento.programa);
    const textura = SizedBox(key: ValueKey('textura'), width: 10, height: 10);
    await t.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: TexturaDesentrelacada(programa: p, colunas: 0, linhas: 0, suportado: true, child: textura),
    ));
    expect(find.byType(ImageFiltered), findsNothing);
  });
}
