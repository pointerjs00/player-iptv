import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/ui/player/ultima_imagem.dart';

void main() {
  testWidgets('guarda a imagem do vídeo que está no ecrã e põe-na por cima até se largar', (t) async {
    final u = UltimaImagem();
    await t.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(width: 64, height: 36, child: u.envolver(const ColoredBox(color: Color(0xFFFF0000)))),
      ),
    ));
    expect(u.imagem, isNull);
    expect(u.sobreposicao(), isNull);

    final guardou = await t.runAsync(() => u.guardar(2));
    expect(guardou, isTrue);
    expect(u.imagem!.width, 128, reason: 'à resolução do ecrã (pixelRatio)');
    expect(u.imagem!.height, 72);
    final p = await t.runAsync(() => u.imagem!.toByteData());
    expect(p!.getUint8(0), 0xFF, reason: 'é a imagem do vídeo (vermelho)');
    expect(p.getUint8(1), 0);

    final s = u.sobreposicao()!;
    await t.pumpWidget(Directionality(textDirection: TextDirection.ltr, child: Stack(children: [s])));
    expect(find.byType(RawImage), findsOneWidget);
    expect(t.widget<RawImage>(find.byType(RawImage)).image, same(u.imagem));
    expect(find.byType(IgnorePointer), findsWidgets, reason: 'nunca apanha toques nem o foco');

    u.largar();
    expect(u.imagem, isNull);
    expect(u.sobreposicao(), isNull);
  });

  testWidgets('guardar outra vez troca a imagem (a anterior é largada)', (t) async {
    final u = UltimaImagem();
    await t.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: SizedBox(width: 10, height: 10, child: u.envolver(const ColoredBox(color: Color(0xFF00FF00))))),
    ));
    await t.runAsync(() => u.guardar(1));
    final primeira = u.imagem!;
    await t.runAsync(() => u.guardar(1));
    expect(u.imagem, isNot(same(primeira)));
    expect(primeira.debugDisposed, isTrue);
    u.largar();
  });

  test('sem o vídeo no ecrã: não guarda nada e não lança', () async {
    final u = UltimaImagem();
    expect(await u.guardar(1), isFalse);
    expect(u.imagem, isNull);
    u.largar();
  });

  testWidgets('a cópia que não acaba não prende a reabertura: desiste ao fim do limite e larga a que chegar tarde',
      (t) async {
    final tarde = Completer<ui.Image>();
    final u = UltimaImagem(copiar: (_, _) => tarde.future, limite: const Duration(milliseconds: 100));
    await t.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: SizedBox(width: 10, height: 10, child: u.envolver(const ColoredBox(color: Color(0xFF0000FF))))),
    ));
    final r = await t.runAsync(() => u.guardar(1).timeout(const Duration(seconds: 2), onTimeout: () => true));
    expect(r, isFalse, reason: 'sem resposta em 100 ms: segue-se com a rodinha');
    expect(u.imagem, isNull);
    final img = await t.runAsync(() async {
      final g = ui.PictureRecorder();
      ui.Canvas(g).drawPaint(ui.Paint());
      return g.endRecording().toImage(2, 2);
    });
    tarde.complete(img!);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    expect(img.debugDisposed, isTrue, reason: 'a que chegou tarde é largada');
    expect(u.imagem, isNull);
  });

  testWidgets('num ecrã grande a cópia fica com 1280 px de largura no máximo (4K: ~33 MB -> ~4 MB)', (t) async {
    final u = UltimaImagem();
    t.view.physicalSize = const Size(3840, 2160);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: SizedBox(width: 1920, height: 1080, child: u.envolver(const ColoredBox(color: Color(0xFF00FF00))))),
    ));
    expect(await t.runAsync(() => u.guardar(2)), isTrue);
    expect(u.imagem!.width, 1280);
    expect(u.imagem!.height, 720);
    u.largar();
  });
}
