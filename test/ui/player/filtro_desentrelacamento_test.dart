import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/ui/design/escala_interface.dart';
import 'package:player_iptv/ui/player/configuracao_mpv.dart';
import 'package:player_iptv/ui/player/desentrelacamento.dart';
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

  testWidgets('com Impeller, programa e tamanho: a textura vai dentro do filtro (shader reutilizado)', (t) async {
    final p = await t.runAsync(FiltroDesentrelacamento.programa);
    final shaders = <ui.FragmentShader>[];
    ui.ImageFilter filtro(ui.FragmentShader s) {
      shaders.add(s);
      return ui.ImageFilter.blur(sigmaX: 0.1, sigmaY: 0.1); // o shader só existe com o Impeller
    }

    Widget arvore(int linhasNoEcra) => Directionality(
          textDirection: TextDirection.ltr,
          child: TexturaDesentrelacada(
              programa: p,
              colunas: 1920,
              linhas: 1080,
              linhasNoEcra: linhasNoEcra.toDouble(),
              suportado: true,
              filtro: filtro,
              child: const SizedBox(key: ValueKey('textura'), width: 10, height: 10)),
        );
    await t.pumpWidget(arvore(1080));
    expect(find.byType(ImageFiltered), findsOneWidget);
    expect(find.descendant(of: find.byType(ImageFiltered), matching: find.byKey(const ValueKey('textura'))), findsOneWidget);
    await t.pumpWidget(arvore(1080));
    expect(shaders.length, 2);
    expect(identical(shaders[0], shaders[1]), isTrue, reason: 'o mesmo FragmentShader em cada build');

    // imagem reduzida no ecrã (ex.: superfície 1280x720 com um 1080i): os campos já vêm misturados
    await t.pumpWidget(arvore(720));
    expect(find.byType(ImageFiltered), findsNothing);
    await t.pumpWidget(const SizedBox());
    expect(shaders.first.debugDisposed, isTrue, reason: 'largado com o widget');
  });

  group('quantas linhas do ecrã o vídeo ocupa (o shader só serve se não for reduzido)', () {
    double linhas(Size caixa, double dpr, {BoxFit fit = BoxFit.contain, double? aspecto, double escala = 1, int c = 1920, int l = 1080}) =>
        linhasMostradas(caixa: caixa, dpr: dpr, colunas: c, linhas: l, fit: fit, aspecto: aspecto, escala: escala);

    test('TV 1080p (960x540 a 2x): 1080 linhas para um 1080i -> cabe', () {
      expect(linhas(const Size(960, 540), 2), 1080);
      expect(shaderCabe(linhasVideo: 1080, linhasNoEcra: 1080), isTrue);
    });
    test('superfície do Flutter a 720p com um 1080i: reduzido -> não cabe', () {
      expect(linhas(const Size(1280, 720), 1), 720);
      expect(shaderCabe(linhasVideo: 1080, linhasNoEcra: 720), isFalse);
    });
    test('576i num ecrã 1080: ampliado -> cabe', () {
      expect(linhas(const Size(1920, 1080), 1, c: 720, l: 576), 1080);
      expect(shaderCabe(linhasVideo: 576, linhasNoEcra: 1080), isTrue);
    });
    test('janela pequena no Windows/telemóvel: não cabe', () {
      expect(shaderCabe(linhasVideo: 1080, linhasNoEcra: linhas(const Size(800, 450), 1)), isFalse);
    });
    test('formatos: esticar, preencher, 4:3 e zoom', () {
      expect(linhas(const Size(1920, 1080), 1, fit: BoxFit.fill), 1080);
      expect(linhas(const Size(1920, 800), 1, fit: BoxFit.cover), 1080, reason: 'cobre pela largura');
      expect(linhas(const Size(1920, 1080), 1, aspecto: 4 / 3), 1080);
      expect(linhas(const Size(1920, 1080), 1, escala: 1.25), 1350);
    });
    test('sem tamanho: 0', () {
      expect(linhas(Size.zero, 1), 0);
      expect(linhas(const Size(100, 100), 1, l: 0), 0);
    });
  });

  test('Android: um canal com cara de entrelaçado (1080 a 25) leva o shader; desligado, não', () {
    final e = imagemEntrelacada({'height': '1080', 'container-fps': '25', 'hwdec-current': 'mediacodec'});
    MeioDesentrelacamento m(bool ligado) => meioDesentrelacamento(PlataformaVideo.android,
        ligado: ligado, entrelacada: e, hwdec: 'mediacodec', shaderFlutter: true);
    expect(m(true), MeioDesentrelacamento.shaderFlutter);
    expect(m(false), MeioDesentrelacamento.nenhum);
    final p = imagemEntrelacada({'height': '720', 'container-fps': '50', 'hwdec-current': 'mediacodec'});
    expect(meioDesentrelacamento(PlataformaVideo.android, ligado: true, entrelacada: p, hwdec: 'mediacodec', shaderFlutter: true),
        MeioDesentrelacamento.nenhum);
  });

  testWidgets('as linhas no ecrã acompanham o tamanho (redimensionar muda a decisão do shader)', (t) async {
    final n = ValueNotifier<double?>(null);
    addTearDown(n.dispose);
    Widget arvore(double altura) => Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: altura * 16 / 9,
              height: altura,
              child: MedidorLinhas(
                  linhas: n,
                  medir: (caixa, dpr) => linhasMostradas(
                      caixa: caixa, dpr: dpr, colunas: 1920, linhas: 1080, fit: BoxFit.contain),
                  child: ValueListenableBuilder<double?>(
                    valueListenable: n,
                    builder: (_, v, _) => Text('${v?.round()}'),
                  )),
            ),
          ),
        );
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1920, 1080);
    addTearDown(t.view.reset);
    await t.pumpWidget(arvore(1080));
    await t.pump();
    expect(n.value, 1080);
    expect(find.text('1080'), findsOneWidget);
    await t.pumpWidget(arvore(540));
    await t.pump();
    expect(n.value, 540);
    expect(find.text('540'), findsOneWidget, reason: 'quem depende das linhas é reconstruído');
  });

  testWidgets('dentro da EscalaInterface(0,8) mede o tamanho real no ecrã, não o de antes da escala', (t) async {
    final n = ValueNotifier<double?>(null);
    addTearDown(n.dispose);
    // a escala 0,8 faz o layout a 1/0,8: a caixa vê 2400 x 1350, mas no ecrã ocupa 1920 x 1080
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1920, 1080);
    addTearDown(t.view.reset);
    await t.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: EscalaInterface(
        escala: 0.8,
        child: MedidorLinhas(
          linhas: n,
          medir: (caixa, dpr) => linhasMostradas(caixa: caixa, dpr: dpr, colunas: 1920, linhas: 1080, fit: BoxFit.contain),
          child: const SizedBox.expand(),
        ),
      ),
    ));
    await t.pump();
    expect(n.value, 1080);
  });
}
