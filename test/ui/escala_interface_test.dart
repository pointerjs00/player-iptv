import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/area_gestor.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/dados/preferencias.dart';
import 'package:player_iptv/ui/definicoes/tela_definicoes.dart';
import 'package:player_iptv/ui/design/escala_interface.dart';
import 'package:player_iptv/ui/realce_foco.dart';
import 'package:player_iptv/ui/tema.dart';

import 'ajuda_dpad.dart';

/// Uma janela de [largura]×[altura] lógicos.
void _janela(WidgetTester t, double largura, double altura) {
  t.view.physicalSize = Size(largura, altura);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

/// Como a app (main.dart): a escala por baixo do tema e por cima do Navigator.
Widget _app(Widget home, {double escala = .8}) => MaterialApp(
      theme: temaApp(),
      builder: (_, w) => TemaConformeRealce(child: EscalaInterface(escala: escala, child: w!)),
      home: home,
    );

/// Com o tamanho que a app tem por omissão.
Widget _appPrefs(Preferencias p, Widget home) => MaterialApp(
      theme: temaApp(),
      builder: (_, w) => TemaConformeRealce(child: EscalaConformePreferencias(preferencias: p, child: w!)),
      home: home,
    );

void main() {
  testWidgets('a 80 %: o filho desenha-se numa área 1/0,8 maior (MediaQuery dividida)', (t) async {
    _janela(t, 960, 540);
    late MediaQueryData mq;
    await t.pumpWidget(MediaQuery(
      data: const MediaQueryData(
        size: Size(960, 540),
        padding: EdgeInsets.all(8),
        viewPadding: EdgeInsets.all(16),
        viewInsets: EdgeInsets.only(bottom: 80),
      ),
      child: EscalaInterface(
        escala: .8,
        child: Builder(builder: (context) {
          mq = MediaQuery.of(context);
          return const SizedBox.expand();
        }),
      ),
    ));
    expect(mq.size, const Size(1200, 675));
    expect(mq.padding, const EdgeInsets.all(10));
    expect(mq.viewPadding, const EdgeInsets.all(20));
    expect(mq.viewInsets, const EdgeInsets.only(bottom: 100));
    expect(t.getSize(find.byType(SizedBox).last), const Size(1200, 675));
  });

  testWidgets('a 100 %: devolve o filho tal como está', (t) async {
    _janela(t, 960, 540);
    const filho = SizedBox.expand(key: Key('filho'));
    await t.pumpWidget(const EscalaInterface(escala: 1, child: filho));
    expect(find.descendant(of: find.byType(EscalaInterface), matching: find.byType(Transform)), findsNothing);
    expect(t.getRect(find.byKey(const Key('filho'))), const Rect.fromLTWH(0, 0, 960, 540));
  });

  testWidgets('um toque no centro de um botão no canto inferior direito ativa-o', (t) async {
    _janela(t, 960, 540);
    var tocou = 0;
    await t.pumpWidget(_app(Scaffold(
      body: Align(
        alignment: Alignment.bottomRight,
        child: FilledButton(onPressed: () => tocou++, child: const Text('Canto')),
      ),
    )));
    final r = t.getRect(find.byType(FilledButton));
    // o botão vê-se dentro da janela, no canto (a área de 1200×675 reduzida a 960×540)
    expect(r.right, moreOrLessEquals(960, epsilon: .01));
    expect(r.bottom, moreOrLessEquals(540, epsilon: .01));
    await t.tapAt(r.center);
    await t.pump();
    expect(tocou, 1);
  });

  testWidgets('um diálogo aberto dentro fica com o mesmo tamanho relativo (reduzido como o resto)', (t) async {
    _janela(t, 960, 540);
    Future<Rect> retangulo(double escala) async {
      await t.pumpWidget(_app(
        escala: escala,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const AlertDialog(title: Text('Título'), content: Text('Um diálogo curto.')),
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('Abrir'));
      await t.pumpAndSettle();
      final r = t.getRect(find.descendant(of: find.byType(AlertDialog), matching: find.byType(Material)).first);
      await t.pumpWidget(const SizedBox());
      return r;
    }

    final normal = await retangulo(1);
    final compacto = await retangulo(.8);
    expect(compacto.width, moreOrLessEquals(normal.width * .8, epsilon: .01));
    expect(compacto.height, moreOrLessEquals(normal.height * .8, epsilon: .01));
    // e continua ao centro da janela
    expect(compacto.center.dx, moreOrLessEquals(480, epsilon: .01));
    expect(compacto.center.dy, moreOrLessEquals(270, epsilon: .01));
  });

  group('escalaPara', () {
    late TamanhoInterface tamanho;
    late double escala;
    Future<void> medir(WidgetTester t, TamanhoInterface tam, {TargetPlatform? plataforma}) async {
      tamanho = tam;
      debugDefaultTargetPlatformOverride = plataforma;
      await t.pumpWidget(Builder(builder: (context) {
        escala = escalaPara(context, tamanho);
        return const SizedBox();
      }));
      debugDefaultTargetPlatformOverride = null;
    }

    testWidgets('Compacto: 0,8 na TV e no Windows; 1 no telemóvel', (t) async {
      _janela(t, 400, 800);
      await medir(t, TamanhoInterface.compacto, plataforma: TargetPlatform.android);
      expect(escala, 1, reason: 'telemóvel');
      await medir(t, TamanhoInterface.compacto, plataforma: TargetPlatform.windows);
      expect(escala, .8, reason: 'Windows');
      ecraTvTeste(t);
      await medir(t, TamanhoInterface.compacto, plataforma: TargetPlatform.android);
      expect(escala, .8, reason: 'TV');
    });

    testWidgets('Normal: sempre 1', (t) async {
      await medir(t, TamanhoInterface.normal, plataforma: TargetPlatform.windows);
      expect(escala, 1);
      ecraTvTeste(t);
      await medir(t, TamanhoInterface.normal, plataforma: TargetPlatform.android);
      expect(escala, 1);
    });
  });

  group('Definições › Imagem e som', () {
    late Directory pasta;
    late Biblioteca bib;
    late AreaGestor area;
    late Preferencias prefs;

    setUp(() async {
      pasta = Directory.systemTemp.createTempSync('escala');
      bib = await Biblioteca.abrir(pasta);
      area = await AreaGestor.abrir(pasta);
      prefs = await Preferencias.abrir(pasta);
    });
    tearDown(() {
      try {
        pasta.deleteSync(recursive: true);
      } on FileSystemException {/* Windows */}
    });

    testWidgets('«Tamanho da interface» é a primeira opção; mudar aplica logo e o foco fica na opção', (t) async {
      ecraTvTeste(t, largura: 1280, altura: 720);
      await t.pumpWidget(_appPrefs(prefs, TelaDefinicoes(biblioteca: bib, area: area, preferencias: prefs)));
      await t.pump(const Duration(milliseconds: 400));

      expect(find.text('Tamanho da interface'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Compacto'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Normal'), findsOneWidget);
      expect(t.getRect(find.text('Tamanho da interface')).top, lessThan(t.getRect(find.text('Desentrelaçamento')).top),
          reason: 'a primeira opção');
      // a 80 %: a janela de 1280 lógicos é desenhada como se tivesse 1600
      expect(MediaQuery.sizeOf(t.element(find.text('Tamanho da interface'))).width, 1600);

      // só com o comando: a categoria, DIREITA (Compacto), DIREITA (Normal), OK
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      expect(textosFocados(), 'Imagem e som');
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pump();
      expect(textosFocados(), contains('Compacto'));
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pump();
      expect(textosFocados(), contains('Normal'));
      await t.sendKeyEvent(LogicalKeyboardKey.select);
      await t.pump();

      expect(prefs.tamanhoInterface, TamanhoInterface.normal);
      expect(find.text('Guardado'), findsOneWidget);
      expect(MediaQuery.sizeOf(t.element(find.text('Tamanho da interface'))).width, 1280, reason: 'aplicou logo');
      expect(textosFocados(), contains('Normal'), reason: 'o foco fica na opção');
    });
  });
}
